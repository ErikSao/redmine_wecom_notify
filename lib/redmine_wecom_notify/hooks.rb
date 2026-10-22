module RedmineWecomNotify
  class Hooks < Redmine::Hook::ViewListener
    # 新建问题
    def controller_issues_new_after_save(context = {})
      Notifier.issue_created(context[:issue])
      ''
    rescue => e
      Rails.logger.warn("[wecom_notify] create hook failed: #{e.class}: #{e.message}")
      ''
    end

    # 更新问题：一次保存只发一条，没有跟踪字段变化时不发
    def controller_issues_edit_after_save(context = {})
      journal = context[:journal]
      Notifier.issue_changed(context[:issue], journal) if journal
      ''
    rescue => e
      Rails.logger.warn("[wecom_notify] update hook failed: #{e.class}: #{e.message}")
      ''
    end
  end
end
