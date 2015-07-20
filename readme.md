Redmine Issue
=============

Command line application that allows to manage issues in redmine easily. Optimized for idfly.ru custom workflow.


Installation
------------

```
gem install redmine-issue
redmine-issue set-config secret [YOUR API KEY AT http://HOST/my/account]
redmine-issue set-config address "http://HOST"
```

Workflow
--------

```
# shell shortcuts used

~ 冬 il # redmine-issue list

+-------+------------+-------------------------+-----------------------------+
| id    | priority   | subject                 | info                        |
+-------+------------+-------------------------+-----------------------------+
| #3304 | Noraml     | Task 1                  | Uveliriya                   |
|       | Feedback   |                         | Leonid Shagabutdinov        |
|       |            |                         |                             |
| #3322 | Noraml     | Task 2                  | Uveliriya                   |
|       | New        |                         | Leonid Shagabutdinov        |
|       |            |                         |                             |
+-------+------------+-------------------------+-----------------------------+

~ 冬 id 22 # redmine-issue description 3322

+-----------------+----------------------------------------------------------+
| Id              | 3322                                                     |
| Project         | Uveliriya                                                |
| Tracker         | Разработка                                               |
| Status          | New                                                      |
| Priority        | Noraml                                                   |
| Author          | Leonid Shagabutdinov                                     |
| Assigned_to     | Leonid Shagabutdinov                                     |
| Fixed_version   | 0.2.3                                                    |
| Subject         | Task 2                                                   |
|                 | Description                                              |
| Start_date      | 2015-07-15                                               |
| Done_ratio      | 0                                                        |
| Estimated_hours | 1.0                                                      |
| Spent_hours     | 1.990000069141388                                        |
| Created_on      | 2015-07-15T07:50:34Z                                     |
| Updated_on      | 2015-07-17T11:32:10Z                                     |
+-----------------+----------------------------------------------------------+

~ 冬 is 22 # redmine-issue start 3322

true

~ 冬 ic # redmine-issue complete

true

```

Commands
--------


### list

List issues; arguments is API get params: http://www.redmine.org/projects/redmine/wiki/Rest_Issues;

Example: --project-id 10 --status-id closed;

Default arguments: --assigned-to-id me --status-id open --sort "priority:desc,project"


### description [id]

Get issue description and comments.


### reply [id] -m [message]

Reply to issue; adds comment, sets status "Feedback" and returns issue to responsible user


### start [id]

Starts issue specified by id; starts tracking current issue and spent time and set issue status "In progress"


### pause

Pause current issue; save spent time to issue and untrack current issue.


### cancel

Cancel current issue; untrack current issue without time saving.


### status

Get current issue id and spent time.


### complete [id]

Complete issue; set status "Completed" to issue and returns issue to responsible user; if completes current -
save spent time.


### close [id]

Same as complete but set status "Closed"; you have to have permission to close issues to tun this command.


### config [key]

Displays config value.


### set-config [key] [value]

Sets config value.


Aliases
-------

It is too tricky to type "redmine-issue start" or "redmine-issue list" each time, so I suggest you to put following
aliases to your .zshrc or .bashrc:

* alias il="redmine-issue list"
* alias is="redmine-issue start"
* alias ic="redmine-issue complete"
* alias ip="redmine-issue pause"
* alias id="redmine-issue description"

