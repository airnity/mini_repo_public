import Config

config :ex_aws,
  access_key_id: {:system, "AWS_ACCESS_KEY_ID"},
  security_token: {:system, "AWS_SESSION_TOKEN"},
  secret_access_key: {:system, "AWS_SECRET_ACCESS_KEY"}
