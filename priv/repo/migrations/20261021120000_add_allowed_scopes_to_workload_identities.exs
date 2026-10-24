defmodule Hexpm.Repo.Migrations.AddAllowedScopesToWorkloadIdentities do
  use Ecto.Migration

  def change do
    alter table(:workload_identities) do
      add :allowed_scopes, {:array, :string}, null: false, default: []
    end

    # An identity with API access reaches as far as an organization admin key,
    # so it names its repositories, workflow and environment, whatever the
    # visibility of the repositories.
    create constraint(:workload_identities, :workload_identities_allowed_scopes,
             check:
               "allowed_scopes <@ ARRAY['api:read', 'api:write']::varchar[] AND " <>
                 "(cardinality(allowed_scopes) = 0 OR " <>
                 "(package_id IS NULL AND jsonb_array_length(repositories) > 0 AND " <>
                 "workflow <> '' AND environment <> ''))"
           )
  end
end
