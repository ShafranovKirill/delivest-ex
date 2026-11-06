defmodule DelivestWeb.Client.V1ContractTest do
  use ExUnit.Case, async: true

  @fixture Path.expand("../../../fixtures/s3_v1_contract.json", __DIR__)

  test "selected pre-S3 v1 routes and DTOs remain readable by old clients" do
    old = @fixture |> File.read!() |> Jason.decode!()
    current = DelivestWeb.OpenApi.spec() |> Jason.encode!() |> Jason.decode!()

    assert current["components"]["securitySchemes"]["bearer"] == %{
             "type" => "http",
             "scheme" => "bearer",
             "bearerFormat" => "JWT"
           }

    assert_contract!(old, current)
  end

  test "the gate rejects removed fields, new request requirements, widened response values and nullable output" do
    old = @fixture |> File.read!() |> Jason.decode!()
    current = DelivestWeb.OpenApi.spec() |> Jason.encode!() |> Jason.decode!()

    removed =
      update_in(
        current,
        ["components", "schemas", "ActiveOrder", "properties"],
        &Map.delete(&1, "total_amount")
      )

    mandatory =
      update_in(
        current,
        ["components", "schemas", "CreateOrderRequest", "required"],
        &(&1 ++ ["cart_revision"])
      )

    widened =
      update_in(
        current,
        ["components", "schemas", "ActiveOrder", "properties", "status", "enum"],
        &(&1 ++ ["unknown_new_status"])
      )

    nullable =
      put_in(
        current,
        ["components", "schemas", "ActiveOrder", "properties", "total_amount", "nullable"],
        true
      )

    narrowed_request =
      update_in(
        current,
        ["components", "schemas", "CreateOrderRequest", "properties", "comment"],
        &Map.delete(&1, "nullable")
      )

    for candidate <- [removed, mandatory, widened, nullable, narrowed_request] do
      assert_raise ExUnit.AssertionError, fn -> assert_contract!(old, candidate) end
    end
  end

  defp assert_contract!(old, current) do
    for {path, methods} <- old["paths"], {method, statuses} <- methods do
      operation = get_in(current, ["paths", path, method])
      assert operation, "removed #{String.upcase(method)} #{path}"

      for status <- statuses do
        assert get_in(operation, ["responses", status]),
               "removed response #{status} for #{String.upcase(method)} #{path}"
      end
    end

    for {name, schema} <- old["schemas"] do
      current_schema = get_in(current, ["components", "schemas", name])
      assert current_schema, "removed DTO #{name}"

      assert_compatible(
        schema,
        current_schema,
        name,
        String.ends_with?(name, "Request")
      )
    end
  end

  defp assert_compatible(old, current, path, request?) do
    for key <- ~w(type format $ref) do
      if Map.has_key?(old, key) do
        assert current[key] == old[key], "changed #{path}.#{key}"
      end
    end

    if request? do
      assert old["nullable"] != true or current["nullable"] == true,
             "narrowed accepted nullable request #{path}"
    else
      assert current["nullable"] != true or old["nullable"] == true,
             "widened nullable response #{path}"
    end

    if Map.has_key?(old, "enum") do
      if request? do
        assert Enum.all?(old["enum"], &(&1 in (current["enum"] || []))),
               "removed accepted request enum at #{path}"
      else
        assert current["enum"] == old["enum"], "changed response enum #{path}"
      end
    end

    required = current["required"] || []

    if request? do
      assert Enum.all?(required, &(&1 in (old["required"] || []))),
             "new required v1 request field at #{path}"
    else
      assert Enum.all?(old["required"] || [], &(&1 in required)),
             "removed required response field at #{path}"
    end

    if old["items"] do
      assert current["items"], "removed array items at #{path}"
      assert_compatible(old["items"], current["items"], "#{path}[]", request?)
    end

    for {field, old_field} <- old["properties"] || %{} do
      current_field = get_in(current, ["properties", field])
      assert current_field, "removed #{path}.#{field}"
      assert_compatible(old_field, current_field, "#{path}.#{field}", request?)
    end
  end
end
