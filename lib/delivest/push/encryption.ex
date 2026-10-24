defmodule Delivest.Push.Encryption do
  @record_size 4096

  def encrypt(plaintext, p256dh, auth) do
    client_public = decode(p256dh)
    {server_public, server_private} = :crypto.generate_key(:ecdh, :prime256v1)
    shared_secret = :crypto.compute_key(:ecdh, client_public, server_private, :prime256v1)
    salt = :crypto.strong_rand_bytes(16)

    key_info = "WebPush: info" <> <<0>> <> client_public <> server_public
    ikm = hkdf(decode(auth), shared_secret, key_info, 32)
    content_key = hkdf(salt, ikm, "Content-Encoding: aes128gcm" <> <<0>>, 16)
    nonce = hkdf(salt, ikm, "Content-Encoding: nonce" <> <<0>>, 12)

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(
        :aes_128_gcm,
        content_key,
        nonce,
        plaintext <> <<2>>,
        <<>>,
        true
      )

    salt <>
      <<@record_size::32, byte_size(server_public)::8>> <> server_public <> ciphertext <> tag
  end

  def hkdf(salt, ikm, info, length) do
    prk = :crypto.mac(:hmac, :sha256, salt, ikm)
    :crypto.mac(:hmac, :sha256, prk, info <> <<1>>) |> binary_part(0, length)
  end

  defp decode(string), do: Base.url_decode64!(string, padding: false)
end
