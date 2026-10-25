defmodule Delivest.Net.TagIcons do
  @icons ~w(
    flame sparkles pepper leaf mood-kid discount star trophy crown medal
    thumb-up heart chef-hat gift percentage clock bolt confetti seedling plant
    salad wheat-off milk-off nut barbell scale heartbeat snowflake temperature soup
    meat fish cheese egg mushroom carrot lemon coffee cake ice-cream
  )

  def names, do: @icons

  def path(name), do: "/images/tag-icons/#{name}.svg"

  def url(name), do: DelivestWeb.Endpoint.static_url() <> path(name)
end
