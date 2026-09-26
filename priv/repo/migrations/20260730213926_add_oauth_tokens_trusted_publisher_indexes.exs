defmodule Hexpm.Repo.Migrations.AddOauthTokensTrustedPublisherIndexes do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    create_if_not_exists index(:oauth_tokens, [:trusted_publisher_id], concurrently: true)

    # OIDC jti must never be reusable, including after token revoke/expiry.
    create_if_not_exists unique_index(
                           :oauth_tokens,
                           [:grant_reference, :client_id],
                           where:
                             "grant_type = 'trusted_publisher' AND grant_reference IS NOT NULL",
                           name: :oauth_tokens_trusted_publisher_grant_reference_client_id_index,
                           concurrently: true
                         )
  end

  def down do
    drop_if_exists index(:oauth_tokens, [:grant_reference, :client_id],
                     name: :oauth_tokens_trusted_publisher_grant_reference_client_id_index,
                     concurrently: true
                   )

    drop_if_exists index(:oauth_tokens, [:trusted_publisher_id], concurrently: true)
  end
end
