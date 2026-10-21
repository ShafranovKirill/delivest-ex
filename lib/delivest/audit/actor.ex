defmodule Delivest.Audit.Actor do
  alias Delivest.Identity.{Client, Staff}

  def describe(%Staff{} = staff),
    do: %{actor_type: :staff, actor_id: staff.id, actor_name: staff.name || staff.login}

  def describe(%Client{} = client),
    do: %{actor_type: :client, actor_id: client.id, actor_name: client.name || client.phone}

  def describe(:system), do: %{actor_type: :system, actor_id: nil, actor_name: nil}
  def describe(_guest), do: %{actor_type: :guest, actor_id: nil, actor_name: nil}

  def label(%{actor_type: type, actor_name: nil}), do: to_string(type)
  def label(%{actor_type: type, actor_name: name}), do: "#{type}:#{name}"
end
