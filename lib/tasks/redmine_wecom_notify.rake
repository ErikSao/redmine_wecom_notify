namespace :redmine do
  namespace :wecom_notify do
    desc '推送超期问题汇总到企业微信群机器人'
    task :overdue => :environment do
      RedmineWecomNotify::Notifier.overdue_digest
    end
  end
end
