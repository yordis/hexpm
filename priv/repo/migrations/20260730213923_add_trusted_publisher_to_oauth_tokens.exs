defmodule Hexpm.Repo.Migrations.AddTrustedPublisherToOauthTokens do
  use Ecto.Migration

  def up do
    alter table(:oauth_tokens) do
      add_if_not_exists :trusted_publisher_id,
                        references(:trusted_publishers, on_delete: :delete_all, validate: false)
    end

    drop_if_exists constraint(:oauth_tokens, :user_or_organization_required)

    create constraint(:oauth_tokens, :user_or_organization_or_trusted_publisher_required,
             check:
               "user_id IS NOT NULL OR organization_id IS NOT NULL OR trusted_publisher_id IS NOT NULL",
             validate: false
           )
  end

  def down do
    drop_if_exists constraint(:oauth_tokens, :user_or_organization_or_trusted_publisher_required)

    create constraint(:oauth_tokens, :user_or_organization_required,
             check: "user_id IS NOT NULL OR organization_id IS NOT NULL"
           )

    alter table(:oauth_tokens) do
      remove_if_exists :trusted_publisher_id, :bigint
    end
  end
end
