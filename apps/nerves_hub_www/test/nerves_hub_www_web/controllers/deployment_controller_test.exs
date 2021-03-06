defmodule NervesHubWWWWeb.DeploymentControllerTest do
  use NervesHubWWWWeb.ConnCase.Browser, async: true

  alias NervesHubWebCore.{AuditLogs, Deployments, Deployments.Deployment, Fixtures}
  alias NervesHubWWWWeb.DeploymentLive

  describe "index" do
    test "lists all deployments", %{conn: conn, current_user: user, current_org: org} do
      product = Fixtures.product_fixture(user, org)

      conn = get(conn, product_deployment_path(conn, :index, product.id))
      assert html_response(conn, 200) =~ "Deployments"
    end
  end

  describe "new deployment" do
    test "renders form with valid request params", %{
      conn: conn,
      current_user: user,
      current_org: org,
      org_key: org_key
    } do
      product = Fixtures.product_fixture(user, org)
      firmware = Fixtures.firmware_fixture(org_key, product)

      conn =
        get(
          conn,
          product_deployment_path(conn, :new, product.id),
          deployment: %{firmware_id: firmware.id}
        )

      assert html_response(conn, 200) =~ "Create Deployment"

      assert html_response(conn, 200) =~ product_deployment_path(conn, :create, product.id)
    end

    test "redirects with invalid firmware", %{conn: conn, current_user: user, current_org: org} do
      product = Fixtures.product_fixture(user, org)

      conn =
        get(conn, product_deployment_path(conn, :new, product.id), deployment: %{firmware_id: -1})

      assert redirected_to(conn, 302) =~ product_deployment_path(conn, :new, product.id)
    end

    test "renders select firmware when no firmware_id is passed", %{
      conn: conn,
      current_user: user,
      current_org: org,
      org_key: org_key
    } do
      product = Fixtures.product_fixture(user, org)
      Fixtures.firmware_fixture(org_key, product)
      conn = get(conn, product_deployment_path(conn, :new, product.id))

      assert html_response(conn, 200) =~ "Select Firmware for New Deployment"
      assert html_response(conn, 200) =~ product_deployment_path(conn, :create, product.id)
    end

    test "redirects to firmware upload firmware_id is passed and no firmwares are found" do
      user = Fixtures.user_fixture(%{email: "new@org.com"})
      org = Fixtures.org_fixture(user, %{name: "empty org"})
      product = Fixtures.product_fixture(user, org)

      conn =
        build_conn()
        |> Map.put(:assigns, %{org: org})
        |> init_test_session(%{"auth_user_id" => user.id, "current_org_id" => org.id})

      conn = get(conn, product_deployment_path(conn, :new, product.id))

      assert redirected_to(conn, 302) =~ product_firmware_path(conn, :upload, product.id)
    end
  end

  describe "create deployment" do
    test "redirects to index when data is valid", %{
      conn: conn,
      current_user: user,
      current_org: org,
      org_key: org_key
    } do
      product = Fixtures.product_fixture(user, org)

      firmware =
        Fixtures.firmware_fixture(org_key, product, %{
          version: "relatively unusual version"
        })

      deployment_params = %{
        firmware_id: firmware.id,
        org_id: org.id,
        name: "Test Deployment ABC",
        tags: "beta, beta-edge",
        version: "< 1.0.0",
        is_active: true
      }

      # check that we end up in the right place
      create_conn =
        post(
          conn,
          product_deployment_path(conn, :create, product.id),
          deployment: deployment_params
        )

      assert redirected_to(create_conn, 302) =~
               product_deployment_path(create_conn, :index, product.id)

      # check that the proper creation side effects took place
      conn = get(conn, product_deployment_path(conn, :index, product.id))
      assert html_response(conn, 200) =~ deployment_params.name
      assert html_response(conn, 200) =~ "Inactive"
      assert html_response(conn, 200) =~ firmware.version
    end

    test "audits on success", %{conn: conn, current_org: org, fixture: fixture} do
      %{firmware: firmware, product: product} = fixture

      deployment_params = %{
        firmware_id: firmware.id,
        org_id: org.id,
        name: "Test Deployment ABC",
        tags: "beta, beta-edge",
        version: "< 1.0.0"
      }

      create_conn =
        post(
          conn,
          product_deployment_path(conn, :create, product.id),
          deployment: deployment_params
        )

      redirect_path = product_deployment_path(create_conn, :index, product.id)

      assert redirected_to(create_conn, 302) =~ redirect_path

      conn = get(create_conn, redirect_path)
      assert get_flash(conn, :info) == "Deployment created"

      [%{resource_type: resource_type, params: params}] = AuditLogs.logs_by(fixture.user)
      assert resource_type == Deployment
      assert params["firmware_id"] == deployment_params.firmware_id
      assert params["org_id"] == deployment_params.org_id
      assert params["name"] == deployment_params.name
    end
  end

  describe "edit deployment" do
    test "edits the chosen resource", %{
      conn: conn,
      current_user: user,
      current_org: org,
      org_key: org_key
    } do
      product = Fixtures.product_fixture(user, org)
      firmware = Fixtures.firmware_fixture(org_key, product)
      deployment = Fixtures.deployment_fixture(firmware)

      conn = get(conn, product_deployment_path(conn, :edit, product.id, deployment))
      assert html_response(conn, 200) =~ "Edit"

      assert html_response(conn, 200) =~
               product_deployment_path(conn, :update, product.id, deployment)
    end
  end

  describe "update deployment" do
    test "update the chosen resource", %{
      conn: conn,
      current_user: user,
      current_org: org,
      org_key: org_key
    } do
      product = Fixtures.product_fixture(user, org)
      firmware = Fixtures.firmware_fixture(org_key, product)
      deployment = Fixtures.deployment_fixture(firmware)

      conn =
        put(
          conn,
          product_deployment_path(conn, :update, product.id, deployment),
          deployment: %{
            "version" => "4.3.2",
            "tags" => "new, tags, now",
            "name" => "not original",
            "firmware_id" => firmware.id
          }
        )

      {:ok, reloaded_deployment} = Deployments.get_deployment(product, deployment.id)

      assert redirected_to(conn, 302) =~
               product_deployment_path(conn, DeploymentLive.Show, product.id, deployment)

      assert reloaded_deployment.name == "not original"
      assert reloaded_deployment.conditions["version"] == "4.3.2"
      assert Enum.sort(reloaded_deployment.conditions["tags"]) == Enum.sort(~w(new tags now))
    end

    test "audits on success", %{conn: conn, fixture: fixture} do
      %{deployment: deployment, product: product} = fixture

      params = %{"tags" => "new_tag", "version" => "> 0.1.0"}

      update_conn =
        put(
          conn,
          product_deployment_path(conn, :update, product.id, deployment),
          deployment: params
        )

      redirect_path = product_deployment_path(update_conn, :index, product.id)

      assert redirected_to(update_conn, 302) =~ redirect_path

      conn = get(update_conn, redirect_path)
      assert get_flash(conn, :info) == "Deployment updated"

      [audit_log] = AuditLogs.logs_for(deployment)

      assert audit_log.resource_type == Deployment
      assert Map.has_key?(audit_log.changes, "conditions")
    end
  end

  describe "delete deployment" do
    test "deletes chosen resource", %{
      conn: conn,
      current_user: user,
      current_org: org,
      org_key: org_key
    } do
      product = Fixtures.product_fixture(user, org)
      firmware = Fixtures.firmware_fixture(org_key, product)
      deployment = Fixtures.deployment_fixture(firmware)

      conn = delete(conn, product_deployment_path(conn, :delete, product.id, deployment))
      assert redirected_to(conn) == product_deployment_path(conn, :index, product.id)
      assert Deployments.get_deployment(product, deployment.id) == {:error, :not_found}
    end
  end
end
