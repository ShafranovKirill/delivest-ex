defmodule Delivest.Integrations.YandexAds.Secret do
  @moduledoc "Authenticated encryption for advertising credentials; no fallback key."
  use Ecto.Type

  def type, do: :binary
  def cast(nil), do: {:ok, nil}
  def cast(value) when is_binary(value), do: {:ok, value}
  def cast(_), do: :error
  def dump(nil), do: {:ok, nil}

  def dump(value) when is_binary(value) do
    with {:ok, key} <- key() do
      nonce = :crypto.strong_rand_bytes(12)

      {ciphertext, tag} =
        :crypto.crypto_one_time_aead(:aes_256_gcm, key, nonce, value, "yandex-ads-v1", true)

      {:ok, <<1, nonce::binary, tag::binary, ciphertext::binary>>}
    end
  end

  def dump(_), do: :error
  def load(nil), do: {:ok, nil}

  def load(<<1, nonce::binary-size(12), tag::binary-size(16), ciphertext::binary>>) do
    with {:ok, key} <- key(),
         plaintext when is_binary(plaintext) <-
           :crypto.crypto_one_time_aead(
             :aes_256_gcm,
             key,
             nonce,
             ciphertext,
             "yandex-ads-v1",
             tag,
             false
           ) do
      {:ok, plaintext}
    else
      _ -> :error
    end
  end

  def load(_), do: :error
  def configured?, do: match?({:ok, _}, key())

  defp key do
    encoded =
      Application.get_env(:delivest, :yandex_ads_encryption_key) ||
        System.get_env("YANDEX_ADS_ENCRYPTION_KEY")

    with true <- is_binary(encoded), {:ok, <<_::256>> = key} <- Base.decode64(encoded) do
      {:ok, key}
    else
      _ -> :error
    end
  end
end
