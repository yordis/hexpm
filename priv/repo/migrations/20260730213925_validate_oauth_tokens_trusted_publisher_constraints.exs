defmodule Hexpm.Repo.Migrations.ValidateOauthTokensTrustedPublisherConstraints do
  use Ecto.Migration

  def up do
    execute "ALTER TABLE oauth_tokens VALIDATE CONSTRAINT oauth_tokens_trusted_publisher_id_fkey"

    execute "ALTER TABLE oauth_tokens VALIDATE CONSTRAINT user_or_organization_or_trusted_publisher_required"
  end

  def down do
  end
end
