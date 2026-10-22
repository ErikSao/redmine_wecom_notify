require_relative 'lib/redmine_wecom_notify/notifier'
require_relative 'lib/redmine_wecom_notify/hooks'

Redmine::Plugin.register :redmine_wecom_notify do
  name 'Redmine WeCom Notify'
  author 'eriksao'
  description '新建问题、字段变更、超期提醒推送到企业微信群机器人'
  version '0.1.0'

  settings default: {
    'webhook_url' => '',
    'base_url' => '',
    'user_map' => '',
    'create_fields' => "author_id\ntracker_id\nsubject\nstatus_id\npriority_id\nassigned_to_id\ndue_date\n是否推广\n测试员\n期望测试完成时间",
    'change_fields' => "status_id\nsubject\nassigned_to_id\n是否推广\n设计变更\n变更协同审视单号"
  },
           partial: 'settings/redmine_wecom_notify'
end
