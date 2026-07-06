Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.object_src  :none
    policy.frame_ancestors :none
    policy.base_uri :self
    policy.form_action :self
    policy.img_src     :self, :https, :data
    policy.font_src    :self, :data
    policy.script_src  :self, "https://gc.zgo.at"
    policy.connect_src :self, "https://*.goatcounter.com"
    policy.style_src   :self, :unsafe_inline
  end
end
