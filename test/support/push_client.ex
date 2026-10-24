defmodule Delivest.PushClient do
  alias Delivest.Push.Encryption

  def new do
    {public_key, private_key} = :crypto.generate_key(:ecdh, :prime256v1)
    auth = :crypto.strong_rand_bytes(16)

    %{
      private_key: private_key,
      auth_secret: auth,
      attrs: %{
        "endpoint" => "https://push.example.com/send/#{System.unique_integer([:positive])}",
        "keys" => %{"p256dh" => encode(public_key), "auth" => encode(auth)},
        "locale" => "en"
      }
    }
  end

  def decrypt(client, body) do
    <<salt::binary-16, _record_size::32, key_length::8, rest::binary>> = body
    <<server_public::binary-size(key_length), encrypted::binary>> = rest
    client_public = client.attrs["keys"]["p256dh"] |> Base.url_decode64!(padding: false)

    shared_secret = :crypto.compute_key(:ecdh, server_public, client.private_key, :prime256v1)
    key_info = "WebPush: info" <> <<0>> <> client_public <> server_public
    ikm = Encryption.hkdf(client.auth_secret, shared_secret, key_info, 32)
    content_key = Encryption.hkdf(salt, ikm, "Content-Encoding: aes128gcm" <> <<0>>, 16)
    nonce = Encryption.hkdf(salt, ikm, "Content-Encoding: nonce" <> <<0>>, 12)

    ciphertext_length = byte_size(encrypted) - 16
    <<ciphertext::binary-size(ciphertext_length), tag::binary-16>> = encrypted

    plaintext =
      :crypto.crypto_one_time_aead(:aes_128_gcm, content_key, nonce, ciphertext, <<>>, tag, false)

    plaintext |> binary_part(0, byte_size(plaintext) - 1) |> Jason.decode!()
  end

  def subscription_attrs(client) do
    %{
      endpoint: client.attrs["endpoint"],
      p256dh: client.attrs["keys"]["p256dh"],
      auth: client.attrs["keys"]["auth"],
      locale: client.attrs["locale"]
    }
  end

  defp encode(binary), do: Base.url_encode64(binary, padding: false)
end
