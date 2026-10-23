defmodule Hexpm.Repo.Migrations.AddApiAccessToWorkloadIdentities do
  use Ecto.Migration

  def change do
    alter table(:workload_identities) do
      add :api_access, :string
    end

    # An identity with API access reaches as far as an organization admin key,
    # so it names its repositories, workflow and environment, whatever the
    # visibility of the repositories.
    create constraint(:workload_identities, :workload_identities_api_access,
             check:
               "api_access IS NULL OR " <>
                 "(api_access IN ('read', 'write') AND package_id IS NULL AND " <>
                 "jsonb_array_length(repositories) > 0 AND workflow <> '' AND environment <> '')"
           )
  end
end
