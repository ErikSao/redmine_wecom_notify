require 'net/http'
require 'json'
require 'uri'

module RedmineWecomNotify
  module Notifier
    module_function

    # 系统字段的显示名，未列出的直接显示字段名
    FIELD_LABELS = {
      'project_id' => '项目',
      'author_id' => '作者',
      'tracker_id' => '跟踪',
      'subject' => '主题',
      'status_id' => '状态',
      'priority_id' => '优先级',
      'assigned_to_id' => '指派人',
      'due_date' => '计划完成时间',
      'start_date' => '开始日期',
      'category_id' => '类别',
      'fixed_version_id' => '目标版本',
      'description' => '描述',
      'done_ratio' => '完成度',
      'estimated_hours' => '预期时间'
    }.freeze

    # 老配置里还没有这两个键时的默认值
    DEFAULT_FIELDS = {
      'create_fields' => %w[author_id tracker_id subject status_id priority_id assigned_to_id due_date 是否推广 测试员 期望测试完成时间],
      'change_fields' => %w[status_id subject assigned_to_id 是否推广 设计变更 变更协同审视单号]
    }.freeze

    # 新建问题
    def issue_created(issue)
      lines = ['**新建问题**']
      lines << "> 项目：#{issue.project.name}"
      lines << "> 编号：##{issue.id}"

      field_list('create_fields').each do |field|
        value = field_value(issue, field)
        lines << "> #{field_label(field)}：#{value.presence || '未填写'}"
      end

      lines << link(issue)
      send_lines(lines)
    end

    # 问题变更：一次保存只发一条，列出所有被跟踪字段的前后值
    def issue_changed(issue, journal)
      allowed = field_list('change_fields')
      changes = {}
      journal.details.each do |detail|
        field = detail_field(detail)
        next if field.nil? || !allowed.include?(field)

        changes[field] =
          "#{display_value(detail.old_value, detail)} → #{display_value(detail.value, detail, mention: true)}"
      end
      return if changes.empty?

      lines = ['**问题变更**']
      lines << "> 项目：#{issue.project.name}"
      lines << "> 编号：##{issue.id}"
      allowed.each do |field|
        if changes.key?(field)
          lines << "> #{field_label(field)}：#{changes[field]}"
        else
          value = field_value(issue, field)
          lines << "> #{field_label(field)}：#{value.presence || '未填写'}"
        end
      end
      lines << link(issue)
      send_lines(lines)
    end

    # 超期问题汇总（供定时任务调用）
    def overdue_digest
      issues = Issue.open
                    .where('due_date IS NULL OR due_date < ?', Date.today)
                    .includes(:project, :status, :assigned_to, :author)
                    .order(:due_date, :id)
      return if issues.empty?

      lines = ['**<font color="warning">超期工单问题</font>**']
      lines << "> 共 #{issues.size} 个问题超过计划完成时间"

      issues.each do |issue|
        if issue.due_date.nil?
          due_text = '未设置'
          overdue_text = '已超期（未填写计划完成时间）'
        else
          due_text = issue.due_date.to_s
          overdue_text = "已超期 #{(Date.today - issue.due_date).to_i} 天"
        end
        lines << "> [#{issue.project.name}] ##{issue.id} #{issue.subject}"
        lines << "> 作者：#{name_with_mention(issue.author) || '未知'} 指派人：#{name_with_mention(issue.assigned_to) || '未指派'}　计划完成：#{due_text}　#{overdue_text}"
      end
      send_lines(lines)
    end

    # 配置页里的字段列表，一行一个；# 开头为注释
    def field_list(key)
      settings = plugin_settings
      raw = settings.key?(key) ? settings[key].to_s : DEFAULT_FIELDS[key].join("\n")
      raw.each_line.map(&:strip).reject {|line| line.empty? || line.start_with?('#')}
    end

    def plugin_settings
      Setting.plugin_redmine_wecom_notify || {}
    end

    def field_label(field)
      FIELD_LABELS[field] || field
    end

    # 新建问题时的字段取值
    def field_value(issue, field)
      case field
      when 'status_id' then issue.status&.name
      when 'assigned_to_id' then name_with_mention(issue.assigned_to) || '未指派'
      when 'author_id' then display_name(issue.author)
      when 'priority_id' then issue.priority&.name
      when 'tracker_id' then issue.tracker&.name
      when 'category_id' then issue.category&.name
      when 'fixed_version_id' then issue.fixed_version&.name
      when 'project_id' then issue.project&.name
      when 'description' then truncate_text(issue.description)
      when 'start_date', 'due_date' then issue.send(field) || '未设置'
      else
        if issue.respond_to?(field)
          value = issue.send(field)
          if value.is_a?(ActiveRecord::Base)
            value.respond_to?(:name) ? value.name : value.id
          elsif value.is_a?(Date) || value.is_a?(Time)
            value.to_s
          else
            value
          end
        else
          truncate_text(custom_value(issue, field))
        end
      end
    end

    # 变更明细对应的字段标识：系统字段用属性名，自定义字段用名称
    def detail_field(detail)
      if detail.property == 'attr'
        detail.prop_key
      elsif detail.property == 'cf'
        detail.custom_field&.name
      end
    end

    def display_value(value, detail, mention: false)
      if detail.property == 'attr' && detail.prop_key == 'assigned_to_id'
        return '未指派' if value.nil? || value.to_s.empty?
        if mention
          user = User.find_by(:id => value)
          return name_with_mention(user) || '未指派'
        end
      end
      return '空' if value.nil? || value.to_s.empty?

      if detail.property == 'attr'
        format_attr(value, detail.prop_key)
      elsif detail.property == 'cf'
        case detail.custom_field&.field_format
        when 'user'
          display_name(User.find_by(:id => value)) || value.to_s
        when 'bool'
          value.to_s == '1' ? '是' : '否'
        else
          value.to_s.truncate(200)
        end
      else
        value.to_s.truncate(200)
      end
    end

    def format_attr(value, key)
      case key
      when 'status_id' then IssueStatus.find_by(:id => value)&.name || value.to_s
      when 'assigned_to_id' then display_name(User.find_by(:id => value)) || '未指派'
      when 'author_id' then display_name(User.find_by(:id => value)) || value.to_s
      when 'priority_id' then IssuePriority.find_by(:id => value)&.name || value.to_s
      when 'tracker_id' then Tracker.find_by(:id => value)&.name || value.to_s
      when 'category_id' then IssueCategory.find_by(:id => value)&.name || value.to_s
      when 'fixed_version_id' then Version.find_by(:id => value)&.name || value.to_s
      when 'project_id' then Project.find_by(:id => value)&.name || value.to_s
      else value.to_s.truncate(200)
      end
    end

    def truncate_text(text)
      text.to_s.truncate(200)
    end

    # 按自定义字段名称取值，返回格式化后的字符串
    def custom_value(issue, name)
      cfv = issue.custom_field_values.detect {|v| v.custom_field.name == name}
      return nil if cfv.nil?

      value = cfv.value
      case cfv.custom_field.field_format
      when 'user'
        value.present? ? display_name(User.find_by(:id => value)) : nil
      when 'bool'
        value.to_s == '1' ? '是' : '否'
      else
        value.is_a?(Array) ? value.reject(&:blank?).join('、') : value
      end
    end

    # 输出 @ 形式；没有映射时 mention_tag 会退化成 @登录名
    def name_with_mention(user)
      return nil if user.nil?

      mention_tag(user).presence || display_name(user)
    end

    # 中文姓名不带空格（姓氏+名字），其它语言沿用 Redmine 的显示格式
    def display_name(user)
      return nil if user.nil?

      first = user.firstname.to_s
      last = user.lastname.to_s
      if first.match?(/\A[\p{Han}]+\z/) && last.match?(/\A[\p{Han}]+\z/)
        "#{last}#{first}"
      else
        user.name
      end
    end

    # 有映射用 <@userid> 真 @；没有映射退化成 @登录名 纯文本，消息照常发送
    def mention_tag(user)
      return '' if user.nil?

      userid = lookup_userid(user)
      return "<@#{userid}>" if userid.present?

      login = user.login.to_s.strip
      login.empty? ? '' : "@#{login}"
    end

    # 依次尝试登录名、显示名、姓+名、名+姓，并忽略空格差异
    def lookup_userid(user)
      map = wecom_userids
      user_keys(user).each do |key|
        return map[key] if map.key?(key)

        compact = key.gsub(/\s+/, '')
        hit = map.find {|k, _| k.gsub(/\s+/, '') == compact}
        return hit[1] if hit
      end
      nil
    end

    def user_keys(user)
      first = user.firstname.to_s
      last = user.lastname.to_s
      keys = [user.login.to_s, user.name.to_s]
      keys << "#{last}#{first}" unless first.empty? || last.empty?
      keys << "#{first}#{last}" unless first.empty? || last.empty?
      keys.map(&:strip).reject(&:empty?)
    end

    # 解析插件配置页上的「用户映射」，一行一条：登录名: userid
    def wecom_userids
      raw = plugin_settings['user_map'].to_s
      return {} if raw.strip.empty?

      if @wecom_userids_raw != raw
        @wecom_userids = raw.each_line.each_with_object({}) do |line, map|
          text = line.strip
          next if text.empty? || text.start_with?('#')

          key, value = text.split(/[:：]/, 2)
          map[key.strip] = value.strip if key.present? && value.present?
        end
        @wecom_userids_raw = raw
      end
      @wecom_userids
    end

    def link(issue)
      "[查看详情](#{base_url}/issues/#{issue.id})"
    end

    # 优先用配置页的站点地址，未配置时回退到 Redmine 的协议 + 主机名
    def base_url
      configured = plugin_settings['base_url'].to_s.strip
      return configured.chomp('/') if configured.present?

      root = Redmine::Utils.relative_url_root.to_s
      "#{Setting.protocol}://#{Setting.host_name}#{root}"
    end

    # 按 3800 字节分片，避免超过企业微信 markdown 的 4096 字节上限
    def send_lines(lines)
      url = plugin_settings['webhook_url'].to_s.strip
      return if url.empty?

      chunks = []
      buf = []
      size = 0
      lines.each do |line|
        line = line.to_s
        line = "#{line[0, 1200]}…" if line.length > 1200
        len = line.bytesize + 1
        if size + len > 3800 && buf.any?
          chunks << buf.join("\n")
          buf = []
          size = 0
        end
        buf << line
        size += len
      end
      chunks << buf.join("\n") if buf.any?

      chunks.each_with_index do |content, index|
        sleep 1 if index.positive?
        post(url, content)
      end
    end

    def post(url, content)
      uri = URI(url)
      proxy = uri.find_proxy
      http =
        if proxy
          Net::HTTP::Proxy(proxy.host, proxy.port, proxy.user, proxy.password).new(uri.host, uri.port)
        else
          Net::HTTP.new(uri.host, uri.port)
        end
      http.use_ssl = (uri.scheme == 'https')
      http.open_timeout = 3
      http.read_timeout = 5

      req = Net::HTTP::Post.new(uri.request_uri, 'Content-Type' => 'application/json; charset=utf-8')
      req.body = {:msgtype => 'markdown', :markdown => {:content => content}}.to_json
      res = http.request(req)
      Rails.logger.info("[wecom_notify] #{res.code} #{res.body}")
    rescue => e
      Rails.logger.warn("[wecom_notify] #{e.class}: #{e.message}")
    end
  end
end
