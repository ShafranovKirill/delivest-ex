defmodule DelivestWeb.Plugs.Locale do
  @behaviour Plug
  import Plug.Conn

  @supported_locales ["en", "ru"]

  def default_locale do
    Application.get_env(:delivest, :default_locale, "en")
  end

  def supported_locales, do: @supported_locales

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    locale = get_session(conn, :locale) || default_locale()
    set_locale(locale)
    conn
  end

  def restore_from_session(session) do
    locale = Map.get(session, "locale", default_locale())
    set_locale(locale)
    locale
  end

  def set_locale(locale) when locale in @supported_locales do
    Gettext.put_locale(DelivestWeb.Gettext, locale)
  end

  def set_locale(_), do: set_locale(default_locale())
end
