require 'json'
require 'shellwords'
require 'terminal-table'
require 'cgi'
require 'date'
require 'net/http'
require 'fileutils'

module RedmineIssue

  STATUS_INPROGRESS = 2
  STATUS_COMPLETED = 3
  STATUS_FEEDBACK = 4
  STATUS_CLOSED = 5

  CONFIG_PATH = '~/.config/redmine-issue/config'
  CONFIG = JSON.parse(File.read(File.expand_path(CONFIG_PATH)))

  class Undefined; end

  def self.config(key, value = Undefined.new())
    if value.instance_of?(Undefined) && !CONFIG.has_key?(key)
      raise "#{key} should be set in config"
    end

    return CONFIG.fetch(key, value)
  end

  def self.set_config(key, value)
    if value.nil?()
      CONFIG.delete(key)
    else
      CONFIG[key] = value
    end

    FileUtils.mkdir_p(File.dirname(CONFIG_PATH))
    new_config = JSON.pretty_generate(CONFIG)
    File.write(File.expand_path(CONFIG_PATH), new_config)
  end

  def self.request(method, get = {}, data = nil, options = {method: 'POST'})
    query =
      get.
      collect() { |key, value |
        CGI.escape(key.to_s()) + '=' + CGI.escape(value.to_s())
      }.
      join('&')

    uri = URI(config('address') + '/' + method + '.json?' + query)

    if data.nil?()
      request = Net::HTTP::Get.new(uri)
    else
      if options[:method] == 'POST'
        request = Net::HTTP::Post.new(uri)
      elsif  options[:method] == 'PUT'
        request = Net::HTTP::Put.new(uri)
      else
        raise 'Wrong request method'
      end
    end

    request['X-Redmine-API-Key'] = config('secret')
    request['Content-Type'] = 'application/json'

    if !data.nil?()
      request.body = JSON.generate(data)
    end

    result = Net::HTTP.start(uri.hostname, uri.port) { |http|
      http.request(request)
    }

    if result.is_a?(Net::HTTPOK) && result.body == ''
      return true
    end

    begin
      return JSON.parse(result.body)
    rescue => error
      raise "Failed to parse json: #{result} (#{error})"
    end
  end

  def self._split_text(text, length = 60)
    result =
      0.
      upto((text.length / length.to_f()).floor()).
      collect() { |index|
        text[index * length, length]
      }.
      join("\n")

    return result
  end

  def self._expand_issue_id(id)
    if id.nil?()
      return config('current')['id']
    end

    if id.start_with?('#')
      return id[1..-1].to_i()
    end

    found = config('last_listed_issues', []).select() { |found_id|
      found_id.to_s().end_with?(id.to_s())
    }

    if found.length > 1
      raise "Issue #id is ambiguos; specify more digits"
    end

    if found.length == 0
      return id
    end

    return found.first().to_i()
  end

  def self._get_current_elapsed_hours()
    current = config('current', nil)
    if current.nil?() || current['id'].nil?()
      raise 'No active issue in progress'
    end

    seconds =
      DateTime.now().to_time() -
      DateTime.parse(current['started']).to_time()

    hours = (seconds / 3600.0).round(2).to_s()

    return hours
  end

  def self._get_arguments_key(key)
    key = key.gsub('_', '{{__DASH__}}')
    key = key.gsub('-', '_')
    key = key.gsub('{{__DASH__}}', '-')
    return key
  end

  def self._get_console_option(args, option)
    if option.instance_of?(::Array)
      option.each() { |option_item|
        result = _get_console_option(args, option_item)
        if !result.nil?()
          return result
        end
      }

      return nil
    end

    if option.length == 1
      index = args.index('-' + _get_arguments_key(option))
      if !index.nil?()
        return args[index + 1]
      end
    end

    if args.index('--no-' + _get_arguments_key(option))
      return false
    end

    index = args.index('--' + _get_arguments_key(option))
    if index.nil?()
      return nil
    end

    if args[index + 1].nil?()
      return true
    end

    return args[index + 1]
  end

  def self._get_arguments_hash(args)
    result = {}
    args.each_with_index() { |value, index|
      if value.start_with?('--no-')
        result[_get_arguments_key(value[5..-1])] = true
        next
      end

      if value.start_with?('--')
        if args[index + 1].nil?() || args[index + 1].start_with?('--')
          result[_get_arguments_key(value[2..-1])] = true
          next
        end

        result[_get_arguments_key(value[2..-1])] = args[index + 1]
      end
    }

    return result
  end

  def self._get_user_id()
    user_id = config('user_id', nil)
    if !user_id.nil?()
      return user_id
    end

    user_id = request('users/current')['user']['id']
    set_config('user_id', user_id)
    return user_id
  end

  def self._get_responsible_user_id(issue)
    if issue.instance_of?(::Fixnum) || issue.instance_of?(::String)
      issue = request("issues/#{issue}", {include: 'journals'})['issue']
    end

    if !issue.has_key?('journals')
      raise "Issue should have journals to find out adminitrator id"
    end

    user_id = _get_user_id()
    issue['journals'].reverse().each() { |note|
      if note['user']['id'] != user_id
        return note['user']['id']
      end
    }

    return issue['author']['id']
  end

  def self._pause_current(id)
    current = config('current', nil)
    if !current.nil?() && current['id'].to_i() == id.to_i()
      pause()
    end
  end

  def self.list(*args)
    params = _get_arguments_hash(args)

    params['assigned_to_id'] ||= 'me'
    params['status_id'] ||= 'open'
    params['sort'] ||= 'priority:desc,project'
    issues = request('issues', params).fetch('issues')

    ids = issues.collect() { |issue| issue['id'] }

    set_config('last_listed_issues', ids)

    info = [['id', 'priority', 'subject', 'info']]
    info.push(:separator)
    info += issues.collect() { |issue|
      next [
        '#' + issue['id'].to_s(),
        [
          issue.fetch('priority', {})['name'],
          issue.fetch('status', {})['name'],
          " ",
        ].join("\n"),
        _split_text(issue['subject']),
        [
          issue.fetch('project', {})['name'],
          issue.fetch('author', {})['name'],
        ].join("\n")
      ]
    }

    info.pop()

    return Terminal::Table.new(rows: info)
  end

  def self.start(id)
    current = config('current', nil)
    if !current.nil?()
      raise "Can not start; issue #{current['id']} is already " +
        'in progress'
    end

    real_id = _expand_issue_id(id)

    issue = {
      'issue' => {'status_id' => STATUS_INPROGRESS}
    }

    result = request("issues/#{real_id}", {}, issue, {method: 'PUT'})
    set_config('current', {'id' => real_id, 'started' => DateTime.now().to_s()})
    return result
  end

  def self.pause()
    current = config('current', nil)
    if current.nil?()
      raise "No active issue in progress"
    end

    time_entry = {
      'issue_id' => current['id'],
      'hours' => _get_current_elapsed_hours()
    }

    result = request('time_entries', {}, {'time_entry' => time_entry})
    set_config('current', nil)
    return result
  end

  def self.cancel()
    current = config('current', nil)
    if current.nil?()
      raise "No active issue in progress"
    end

    set_config('current', nil)
    return current
  end

  def self.status()
    current = config('current', nil)
    if current.nil?()
      raise "No active issue in progress"
    end

    return "Issue: ##{current['id']}\nTime: #{_get_current_elapsed_hours()}"
  end

  def self.complete(id = nil)
    real_id = _expand_issue_id(id)
    _pause_current(real_id)

    issue = {
      'assigned_to_id' => _get_responsible_user_id(real_id),
      'status_id' => STATUS_COMPLETED,
    }

    return request("issues/#{real_id}", {}, {'issue' => issue}, {method: 'PUT'})
  end

  def self.close(id = nil)
    real_id = _expand_issue_id(id)
    _pause_current(real_id)

    issue = {
      'status_id' => STATUS_CLOSED
    }

    return request("issues/#{real_id}", {}, {'issue' => issue}, {method: 'PUT'})
  end

  def self.description(id = nil)
    real_id = _expand_issue_id(id)
    issue = request("issues/#{real_id}", {include: 'journals'})['issue']
    journal = issue.delete('journals')

    info =
      issue.
      collect() { |key, value|
        if value.instance_of?(::Hash)
          if value.has_key?('name')
            value = value['name']
          else
            value = value.to_s()
          end
        end

        [key.capitalize(), _split_text(value.to_s(), 100)]
      }

    comments =
      journal.
      select() { |element|
        !element['notes'].empty?()
      }.
      collect() { |element|
        [element['user']['name'], _split_text(element['notes'], 80)]
      }

    if comments.length > 0
      info.push(['Comments', Terminal::Table.new(rows: comments)])
    end

    return Terminal::Table.new(rows: info)
  end

  def self.reply(*args)
    if args.length > 0 && args[0].match(/^\d+/)
      real_id = _expand_issue_id(args[0])
    else
      id = _get_console_option(args, ['i', 'issue'])
      real_id = _expand_issue_id(id)
    end

    message = _get_console_option(args, ['m', 'message'])

    issue = {
      'assigned_to_id' => _get_responsible_user_id(real_id),
      'status' => STATUS_FEEDBACK,
      'notes' => message,
    }

    return request("issues/#{real_id}", {}, {'issue' => issue}, {method: 'PUT'})
  end

  def self.help()
    return <<-TEXT
USAGE: redmine-issue [command] [args]

Manage redmine issues.

Commands:

  list

    List issues; arguments is API get params: http://www.redmine.org/projects/redmine/wiki/Rest_Issues;
    Example: --project-id 10 --status-id closed; default arguments: --assigned-to-id me --status-id open
      --sort "priority:desc,project"

  description [id]

    Get issue description and comments

  reply [id] -m message

    Reply to issue; adds comment, sets status "Feedback" and returns issue to responsible user

  start id

    Starts issue specified by id; starts tracking current issue and spent time and set issue status "In progress"

  pause

    Pause current issue; save spent time to issue and untrack current issue.

  cancel

    Cancel current issue; untrack current issue without time saving.

  status

    Get current issue id and spent time.

  complete [id]

    Complete issue; set status "Completed" to issue and returns issue to responsible user; if completes current -
    save spent time.

  close [id]

    Same as complete but set status "Closed"; you have to have permission to close issues to tun this command.

  config key

    Displays config value.

  set-config key value

    Sets config value.

TEXT
  end

end