defmodule Delivest.Net.Products.ProductImportWorker do
  use Oban.Worker, queue: :default, max_attempts: 1

  require Logger
  alias Delivest.Repo
  alias Delivest.Identity.Staff
  alias Delivest.Net.{Categories, Products}

  NimbleCSV.define(Parser, separator: ",", escape: "\"")

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "file_path" => file_path,
          "staff_id" => staff_id,
          "branch_id" => branch_id
        }
      }) do
    staff = Repo.get(Staff, staff_id) |> Repo.preload(:role)

    if staff && File.exists?(file_path) do
      Logger.info(
        "Starting product import for staff #{staff_id} and branch #{branch_id} from file #{file_path}"
      )

      try do
        result = process_csv(staff, branch_id, file_path)
        Logger.info("Product import completed successfully. Result: #{inspect(result)}")

        File.rm(file_path)
        {:ok, result}
      rescue
        e ->
          Logger.error("Product import failed with exception: #{Exception.message(e)}")
          File.rm(file_path)
          {:error, Exception.message(e)}
      end
    else
      Logger.error(
        "Product import failed: staff not found (#{staff_id}) or file missing (#{file_path})"
      )

      {:error, :staff_not_found_or_file_missing}
    end
  end

  defp process_csv(staff, branch_id, file_path) do
    file_path
    |> File.stream!()
    |> Parser.parse_stream()
    |> Stream.drop(1)
    |> Enum.with_index(2)
    |> Enum.reduce({0, []}, fn {row, index}, {imported, errors} ->
      case row do
        [name, price, description, quantity, weight, category_name, external_id] ->
          try do
            case Categories.find_or_create_category_by_name(staff, branch_id, category_name) do
              {:ok, category} ->
                category_id = if category, do: category.id, else: nil

                attrs = %{
                  "name" => String.trim(name),
                  "price" => parse_integer(price),
                  "description" => String.trim(description),
                  "quantity" => parse_integer(quantity),
                  "weight" => parse_integer(weight),
                  "category_id" => category_id,
                  "external_id" => String.trim(external_id),
                  "is_active" => true
                }

                case Products.create_product(staff, branch_id, attrs) do
                  {:ok, _product} ->
                    {imported + 1, errors}

                  {:error, changeset} ->
                    err_msg = format_changeset_errors(changeset)
                    Logger.warning("Row #{index} failed validation: #{err_msg}")
                    {imported, [{index, err_msg} | errors]}
                end

              {:error, reason} ->
                Logger.warning("Row #{index} category error: #{inspect(reason)}")
                {imported, [{index, "Category error: #{inspect(reason)}"} | errors]}
            end
          rescue
            err ->
              Logger.error("Exception on row #{index}: #{inspect(err)}")
              {imported, [{index, "Exception: #{inspect(err)}"} | errors]}
          end

        other ->
          Logger.warning("Row #{index} has invalid column format: #{inspect(other)}")
          {imported, [{index, "Invalid column format: #{inspect(other)}"} | errors]}
      end
    end)
  end

  defp parse_integer(val) when is_binary(val) do
    case Integer.parse(String.trim(val)) do
      {int, _} -> int
      :error -> 0
    end
  end

  defp parse_integer(val) when is_integer(val), do: val
  defp parse_integer(_), do: 0

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)
    |> Enum.join("; ")
  end
end
