defmodule Delivest.Slug do
  @max_length 80

  @translit %{
    "а" => "a",
    "б" => "b",
    "в" => "v",
    "г" => "g",
    "д" => "d",
    "е" => "e",
    "ё" => "e",
    "ж" => "zh",
    "з" => "z",
    "и" => "i",
    "й" => "y",
    "к" => "k",
    "л" => "l",
    "м" => "m",
    "н" => "n",
    "о" => "o",
    "п" => "p",
    "р" => "r",
    "с" => "s",
    "т" => "t",
    "у" => "u",
    "ф" => "f",
    "х" => "h",
    "ц" => "ts",
    "ч" => "ch",
    "ш" => "sh",
    "щ" => "sch",
    "ъ" => "",
    "ы" => "y",
    "ь" => "",
    "э" => "e",
    "ю" => "yu",
    "я" => "ya"
  }

  @format ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/

  def format, do: @format

  @spec slugify(String.t() | nil) :: String.t() | nil
  def slugify(nil), do: nil

  def slugify(text) when is_binary(text) do
    slug =
      text
      |> String.downcase()
      |> String.graphemes()
      |> Enum.map_join(&Map.get(@translit, &1, &1))
      |> :unicode.characters_to_nfd_binary()
      |> String.replace(~r/\p{Mn}/u, "")
      |> String.replace(~r/[^a-z0-9]+/u, "-")
      |> String.trim("-")
      |> String.slice(0, @max_length)
      |> String.trim_trailing("-")

    if slug == "", do: nil, else: slug
  end

  @spec unique(String.t(), (String.t() -> boolean())) :: String.t()
  def unique(base, taken?) when is_binary(base) do
    Stream.iterate(1, &(&1 + 1))
    |> Stream.map(fn
      1 -> base
      n -> "#{String.slice(base, 0, @max_length - 4)}-#{n}"
    end)
    |> Enum.find(&(not taken?.(&1)))
  end
end
