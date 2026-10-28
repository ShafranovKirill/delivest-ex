defmodule Delivest.Push.Vapid do
  alias Delivest.Push.KeyPair
  alias Delivest.Repo

  @ttl_seconds 12 * 3600

  def public_key, do: keys().public_key

  def authorization(endpoint) do
    %{public_key: public_key, private_key: private_key} = keys()
    "vapid t=#{token(endpoint, decode(private_key))}, k=#{public_key}"
  end

  defp token(endpoint, private_key) do
    claims = %{
      aud: origin(endpoint),
      exp: System.system_time(:second) + @ttl_seconds,
      sub: subject()
    }

    input = encode_json(%{typ: "JWT", alg: "ES256"}) <> "." <> encode_json(claims)
    input <> "." <> encode(sign(input, private_key))
  end

  defp sign(input, private_key) do
    der = :crypto.sign(:ecdsa, :sha256, input, [private_key, :prime256v1])
    {:"ECDSA-Sig-Value", r, s} = :public_key.der_decode(:"ECDSA-Sig-Value", der)
    <<r::unsigned-big-256, s::unsigned-big-256>>
  end

  defp origin(endpoint) do
    %URI{scheme: scheme, host: host} = URI.parse(endpoint)
    "#{scheme}://#{host}"
  end

  defp subject do
    case Application.get_env(:delivest, :client_origin) do
      "https://" <> _host = origin -> origin
      _other -> "https://delivest.shafranov.tech"
    end
  end

  defp keys do
    case :persistent_term.get(__MODULE__, nil) do
      nil -> tap(load_or_create(), &:persistent_term.put(__MODULE__, &1))
      keys -> keys
    end
  end

  defp load_or_create do
    Repo.insert!(generate(), on_conflict: :nothing, conflict_target: :id)
    Repo.get!(KeyPair, 1)
  end

  defp generate do
    {public_key, private_key} = :crypto.generate_key(:ecdh, :prime256v1)
    %KeyPair{id: 1, public_key: encode(public_key), private_key: encode(private_key)}
  end

  defp encode_json(map), do: map |> Jason.encode!() |> encode()
  defp encode(binary), do: Base.url_encode64(binary, padding: false)
  defp decode(string), do: Base.url_decode64!(string, padding: false)
end
