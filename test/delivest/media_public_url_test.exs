defmodule Delivest.MediaPublicUrlTest do
  use ExUnit.Case, async: false

  alias Delivest.Media

  describe "generate_public_url/2" do
    test "leaves the port out when it is not configured" do
      media = Application.get_env(:delivest, Delivest.Media)
      on_exit(fn -> Application.put_env(:delivest, Delivest.Media, media) end)

      Application.put_env(:delivest, Delivest.Media, Keyword.put(media, :public_port, nil))

      assert {:ok, "http://s3.test/delivest/a.jpg"} =
               Media.generate_public_url("delivest", "a.jpg")

      s3 = Application.get_env(:ex_aws, :s3)
      on_exit(fn -> Application.put_env(:ex_aws, :s3, s3) end)
      Application.put_env(:ex_aws, :s3, Keyword.put(s3, :port, nil))

      assert {:ok, "http://s3.test/delivest/a.jpg"} =
               Media.generate_public_url("delivest", "a.jpg")
    end

    test "public HTTPS host is independent of the internal S3 endpoint" do
      media = Application.get_env(:delivest, Delivest.Media)
      on_exit(fn -> Application.put_env(:delivest, Delivest.Media, media) end)

      Application.put_env(
        :delivest,
        Delivest.Media,
        media
        |> Keyword.put(:public_host, "media.example.org")
        |> Keyword.put(:public_scheme, "https://")
        |> Keyword.put(:public_port, 443)
      )

      assert {:ok, "https://media.example.org/delivest/a.jpg"} =
               Media.generate_public_url("delivest", "a.jpg")

      assert {:ok, signed} = Media.generate_download_url("delivest-private", "secret.txt")
      assert String.starts_with?(signed, "https://media.example.org/delivest-private/secret.txt?")
      refute String.contains?(signed, "s3.test")
    end
  end
end
