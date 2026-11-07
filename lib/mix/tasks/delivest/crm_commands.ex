defmodule Mix.Tasks.Delivest.CrmCommands do
  use Mix.Task

  @shortdoc "List and resolve durable CRM commands"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, rest, invalid} =
      OptionParser.parse(args,
        strict: [
          id: :integer,
          actor: :string,
          reason: :string,
          limit: :integer,
          confirmed_absent: :boolean
        ]
      )

    if invalid != [], do: Mix.raise("Invalid options: #{inspect(invalid)}")

    alias Delivest.Integrations.Crm.Commands

    case rest do
      ["list"] ->
        Commands.list(Keyword.get(opts, :limit, 100))
        |> Enum.each(&Mix.shell().info(inspect(&1)))

      [action] when action in ["confirmed-effect", "skip", "retry"] ->
        decision =
          if action == "confirmed-effect",
            do: :confirmed_effect,
            else: String.to_existing_atom(action)

        case Commands.resolve(
               opts[:id],
               opts[:actor],
               opts[:reason],
               decision,
               Keyword.get(opts, :confirmed_absent, false)
             ) do
          {:ok, :ok} -> Mix.shell().info("#{action} recorded")
          {:error, reason} -> Mix.raise("#{action} refused: #{inspect(reason)}")
        end

      _ ->
        Mix.raise(
          "Usage: mix delivest.crm_commands list [--limit N] | confirmed-effect|skip|retry --id N --actor STAFF_UUID --reason TEXT [--confirmed-absent]"
        )
    end
  end
end
