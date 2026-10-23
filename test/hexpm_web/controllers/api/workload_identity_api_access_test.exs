defmodule HexpmWeb.API.WorkloadIdentityApiAccessTest do
  use HexpmWeb.ConnCase, async: false
  import Mox
  import Ecto.Query, only: [from: 2]

  alias Hexpm.WorkloadIdentities
  alias Hexpm.WorkloadIdentities.TrustedRepository
  alias Hexpm.WorkloadIdentityHelpers

  setup :verify_on_exit!

  setup do
    WorkloadIdentityHelpers.stub_oidc_discovery()

    repository = insert(:repository)
    organization = repository.organization

    member = insert(:user)
    insert(:organization_user, organization: organization, user: member, role: "write")
    newcomer = insert(:user)
    admin = insert(:user)
    insert(:organization_user, organization: organization, user: admin, role: "admin")

    package =
      insert(:package,
        repository_id: repository.id,
        package_owners: [
          build(:package_owner, user: organization.user),
          build(:package_owner, user: member, level: "maintainer")
        ]
      )

    insert(:release, package: package, version: "1.0.0", has_docs: true)

    insert(:release,
      package: package,
      version: "2.0.0",
      retirement: %Hexpm.Repository.ReleaseRetirement{reason: "security"}
    )

    identity =
      insert(:organization_workload_identity,
        organization: organization,
        api_access: :write,
        workflow: "release.yml",
        environment: "release",
        repositories: [%TrustedRepository{name: "acme/widget", id: "67890"}]
      )

    key_for(organization)

    stub(Hexpm.Billing.Mock, :get, fn _token, _opts -> %{"quantity" => 5} end)
    stub(Hexpm.Billing.Mock, :update, fn _token, _params -> {:ok, %{}} end)

    %{
      repository: repository,
      organization: organization,
      member: member,
      admin: admin,
      newcomer: newcomer,
      package: package,
      identity: identity
    }
  end

  defp token_for(organization, api_access) do
    WorkloadIdentityHelpers.stub_oidc_discovery()

    {:ok, token} =
      [environment: "release"]
      |> WorkloadIdentityHelpers.github_claims()
      |> WorkloadIdentityHelpers.sign_oidc_claims()
      |> WorkloadIdentities.verify_and_mint(
        api_access: api_access,
        owner: {:organization, organization.name}
      )

    "Bearer #{token.access_token}"
  end

  defp request(authorization, method, path, params \\ nil) do
    conn = put_req_header(build_conn(), "authorization", authorization)
    Phoenix.ConnTest.dispatch(conn, HexpmWeb.Endpoint, method, path, params)
  end

  @routes [
    {"orgs show", :get, :read, &__MODULE__.p_org/1, nil, 200},
    {"orgs audit logs", :get, :read, &__MODULE__.p_audit/1, nil, 200},
    {"orgs update", :post, :write, &__MODULE__.p_org/1, %{seats: 5}, 200},
    {"members index", :get, :read, &__MODULE__.p_members/1, nil, 200},
    {"members show", :get, :read, &__MODULE__.p_member/1, nil, 200},
    {"members create", :post, :write, &__MODULE__.p_members/1, &__MODULE__.b_member_create/1,
     403},
    {"members update", :post, :write, &__MODULE__.p_member/1, %{role: "read"}, 200},
    {"members delete", :delete, :write, &__MODULE__.p_member/1, nil, 204},
    {"repos index", :get, :read, &__MODULE__.p_repos/1, nil, 200},
    {"repos show", :get, :read, &__MODULE__.p_repo/1, nil, 200},
    {"packages index", :get, :read, &__MODULE__.p_packages/1, nil, 200},
    {"packages show", :get, :read, &__MODULE__.p_package/1, nil, 200},
    {"packages audit logs", :get, :read, &__MODULE__.p_package_audit/1, nil, 200},
    {"releases show", :get, :read, &__MODULE__.p_release/1, nil, 200},
    {"releases delete", :delete, :write, &__MODULE__.p_release/1, nil, 204},
    {"retire", :post, :write, &__MODULE__.p_retire/1,
     %{reason: "security", message: "See CVE-2026-0001"}, 204},
    {"unretire", :delete, :write, &__MODULE__.p_unretire/1, nil, 204},
    {"docs show", :get, :read, &__MODULE__.p_docs/1, nil, 302},
    {"docs delete", :delete, :write, &__MODULE__.p_docs/1, nil, 204},
    {"owners index", :get, :read, &__MODULE__.p_owners/1, nil, 200},
    {"owners show", :get, :read, &__MODULE__.p_owner/1, nil, 200},
    {"owners create", :put, :write, &__MODULE__.p_new_owner/1, nil, 204},
    {"owners delete", :delete, :write, &__MODULE__.p_member_owner/1, nil, 204},
    {"keys index", :get, :read, &__MODULE__.p_keys/1, nil, 200},
    {"keys show", :get, :read, &__MODULE__.p_key/1, nil, 200},
    {"keys create", :post, :write, &__MODULE__.p_keys/1,
     %{name: "created", permissions: [%{domain: "api"}]}, 201},
    {"keys delete", :delete, :write, &__MODULE__.p_key/1, nil, 200},
    {"keys delete all", :delete, :write, &__MODULE__.p_keys/1, nil, 200}
  ]

  def p_org(c), do: "/api/orgs/#{c.organization.name}"
  def p_audit(c), do: "/api/orgs/#{c.organization.name}/audit-logs"
  def p_members(c), do: "/api/orgs/#{c.organization.name}/members"
  def p_member(c), do: "/api/orgs/#{c.organization.name}/members/#{c.member.username}"
  def b_member_create(c), do: %{name: c.newcomer.username, role: "read"}
  def p_repos(_c), do: "/api/repos"
  def p_repo(c), do: "/api/repos/#{c.repository.name}"
  def p_packages(c), do: "/api/repos/#{c.repository.name}/packages"
  def p_package(c), do: "#{p_packages(c)}/#{c.package.name}"
  def p_package_audit(c), do: "#{p_package(c)}/audit-logs"
  def p_release(c), do: "#{p_package(c)}/releases/1.0.0"
  def p_retire(c), do: "#{p_release(c)}/retire"
  def p_unretire(c), do: "#{p_package(c)}/releases/2.0.0/retire"
  def p_docs(c), do: "#{p_release(c)}/docs"
  def p_owners(c), do: "#{p_package(c)}/owners"
  def p_owner(c), do: "#{p_owners(c)}/#{c.organization.user.username}"
  def p_new_owner(c), do: "#{p_owners(c)}/#{c.admin.username}"
  def p_member_owner(c), do: "#{p_owners(c)}/#{c.member.username}"
  def p_keys(c), do: "/api/orgs/#{c.organization.name}/keys"
  def p_key(c), do: "#{p_keys(c)}/any_key_name"

  defp route(ctx, label) do
    {^label, method, access, path, body, status} = List.keyfind(@routes, label, 0)
    body = if is_function(body), do: body.(ctx), else: body
    %{method: method, access: access, path: path.(ctx), body: body, status: status}
  end

  for {label, _method, _access, _path, _body, _status} <- @routes do
    describe label do
      test "an organization key", ctx do
        r = route(ctx, unquote(label))
        conn = request(key_for(ctx.organization), r.method, r.path, r.body)
        assert conn.status == r.status, conn.resp_body
      end

      test "a write workload identity token", ctx do
        r = route(ctx, unquote(label))
        conn = request(token_for(ctx.organization, :write), r.method, r.path, r.body)
        assert conn.status == r.status
      end

      test "a read workload identity token", ctx do
        r = route(ctx, unquote(label))
        conn = request(token_for(ctx.organization, :read), r.method, r.path, r.body)

        if r.access == :read do
          assert conn.status == r.status
        else
          assert conn.status == 403
          assert [challenge] = get_resp_header(conn, "www-authenticate")
          assert challenge =~ "insufficient_scope"
        end
      end

      test "another organization's token", ctx do
        other = insert(:repository).organization

        insert(:organization_workload_identity,
          organization: other,
          api_access: :write,
          workflow: "release.yml",
          environment: "release",
          repositories: [%TrustedRepository{name: "acme/widget", id: "67890"}]
        )

        r = route(ctx, unquote(label))
        conn = request(token_for(other, :write), r.method, r.path, r.body)

        if r.path == "/api/repos" do
          assert conn.status == 200
        else
          assert conn.status in [403, 404]
          refute conn.status == r.status
        end
      end

      test "a token that only publishes", ctx do
        insert(:organization_workload_identity,
          organization: ctx.organization,
          role: "write",
          workflow: "publish.yml",
          repositories: [%TrustedRepository{name: "acme/widget", id: "67890"}]
        )

        WorkloadIdentityHelpers.stub_oidc_discovery()

        {:ok, token} =
          [workflow: "publish.yml"]
          |> WorkloadIdentityHelpers.github_claims()
          |> WorkloadIdentityHelpers.sign_oidc_claims()
          |> WorkloadIdentities.verify_and_mint(repository: ctx.repository.name)

        r = route(ctx, unquote(label))
        conn = request("Bearer #{token.access_token}", r.method, r.path, r.body)
        assert conn.status in [401, 403, 404]
      end
    end
  end

  describe "attribution" do
    for label <- [
          "members update",
          "members delete",
          "owners create",
          "owners delete",
          "retire",
          "unretire",
          "releases delete",
          "docs delete",
          "keys create",
          "keys delete",
          "keys delete all"
        ] do
      test "#{label} is logged with the workload identity as the actor", ctx do
        r = route(ctx, unquote(label))
        conn = request(token_for(ctx.organization, :write), r.method, r.path, r.body)
        assert conn.status == r.status

        logs = Hexpm.Repo.all(from(al in Hexpm.Accounts.AuditLog, order_by: al.id))
        assert logs != []

        for log <- logs do
          assert log.user_id == nil
          assert log.user_data["workload_identity_id"] == ctx.identity.id
          assert log.user_data["grant_type"] == "workload_identity"
          assert log.organization_id == ctx.organization.id
          if unquote(label) != "keys delete all", do: assert(log.oauth_token_id)
        end
      end
    end
  end

  describe "credentials" do
    test "an API token cannot be exchanged for another token as an API key", ctx do
      client = insert(:oauth_client, allowed_grant_types: ["client_credentials"])
      "Bearer " <> access_token = token_for(ctx.organization, :write)

      conn =
        post(build_conn(), "/api/oauth/token", %{
          "grant_type" => "client_credentials",
          "client_id" => client.client_id,
          "client_secret" => access_token,
          "scope" => "api"
        })

      assert json_response(conn, 400)["error"] == "invalid_client"
    end

    test "an API token does not authenticate a browser route", ctx do
      conn =
        build_conn()
        |> put_req_header("authorization", token_for(ctx.organization, :write))
        |> get("/dashboard")

      assert redirected_to(conn) =~ "/login"
    end

    test "the token is the organization on the auth endpoint", ctx do
      conn = request(token_for(ctx.organization, :read), :get, "/api/auth?domain=api")
      assert conn.status == 204
    end

    test "the token cannot be used for the repository domain", ctx do
      conn =
        request(token_for(ctx.organization, :write), :get, "/api/auth?domain=repository")

      assert conn.status in [401, 403]
    end

    test "a revoked token is refused", ctx do
      authorization = token_for(ctx.organization, :write)

      Hexpm.Repo.update_all(Hexpm.OAuth.Token, set: [revoked_at: DateTime.utc_now()])

      assert request(authorization, :get, "/api/orgs/#{ctx.organization.name}").status == 401
    end

    test "narrowing api access revokes the token", ctx do
      authorization = token_for(ctx.organization, :write)
      assert request(authorization, :get, "/api/orgs/#{ctx.organization.name}").status == 200

      ctx.identity
      |> Ecto.Changeset.change(api_access: nil)
      |> Hexpm.Repo.update!()

      assert request(authorization, :get, "/api/orgs/#{ctx.organization.name}").status == 401
    end
  end

  describe "billing" do
    setup ctx do
      ctx.organization
      |> Ecto.Changeset.change(billing_active: false)
      |> Hexpm.Repo.update!()

      :ok
    end

    test "release delete is refused like an organization key", ctx do
      r = route(ctx, "releases delete")

      key_conn = request(key_for(ctx.organization), r.method, r.path)
      wi_conn = request(token_for(ctx.organization, :write), r.method, r.path)

      assert key_conn.status == 403
      assert wi_conn.status == key_conn.status
    end

    test "reads keep working", ctx do
      r = route(ctx, "releases show")
      assert request(token_for(ctx.organization, :write), r.method, r.path).status == 200
    end
  end

  describe "publish" do
    test "publishes into the organization's repository as the organization does", ctx do
      meta = %{name: "wi_published", version: "1.0.0", description: "Domain-specific language."}

      publish = fn authorization ->
        build_conn()
        |> put_req_header("authorization", authorization)
        |> put_req_header("content-type", "application/octet-stream")
        |> post("/api/repos/#{ctx.repository.name}/publish", create_tar(meta))
      end

      assert publish.(key_for(ctx.organization)).status == 201
      Hexpm.Repo.delete_all(Hexpm.Repository.Release)

      conn = publish.(token_for(ctx.organization, :write))
      assert conn.status == 201, conn.resp_body
    end
  end
end
