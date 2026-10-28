defmodule DelivestWeb.StaffBranchPath do
  @prefix ~r{^/staff/b/[^/]+}
  @uuid ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
  @section ~r{^(/[a-z0-9-]+)+$}

  def home(nil), do: "/staff"
  def home(branch), do: "/staff/b/#{branch.slug}/dashboard"

  def strip(path) when is_binary(path), do: String.replace(path, @prefix, "/staff")
  def strip(path), do: path

  def section(path) when is_binary(path) do
    if Regex.match?(@prefix, path) do
      path
      |> String.replace(@prefix, "")
      |> String.split("/", trim: true)
      |> Enum.take_while(&(not Regex.match?(@uuid, &1)))
      |> Enum.map_join(&("/" <> &1))
      |> case do
        "" -> nil
        section -> section
      end
    end
  end

  def section(_path), do: nil

  def valid_section?(section) when is_binary(section), do: Regex.match?(@section, section)
  def valid_section?(_section), do: false
end
