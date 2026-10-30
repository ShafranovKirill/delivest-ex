defmodule DelivestWeb.Schemas.FranchiseSchemas do
  alias OpenApiSpex.Schema

  defmodule Legal do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "FranchiseLegal",
      type: :object,
      properties: %{
        form: %Schema{type: :string, example: "ООО", nullable: true},
        name: %Schema{type: :string, example: "Вкусная еда", nullable: true},
        inn: %Schema{type: :string, example: "7700000000", nullable: true},
        ogrn: %Schema{type: :string, example: "1027700000000", nullable: true},
        address: %Schema{type: :string, example: "г. Москва, ул. Пушкина, д. 10", nullable: true},
        email: %Schema{type: :string, example: "info@example.com", nullable: true},
        phone: %Schema{type: :string, example: "+79990000000", nullable: true}
      },
      required: [:form, :name, :inn, :ogrn, :address, :email, :phone]
    })
  end

  defmodule DocumentSummary do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "LegalDocumentSummary",
      type: :object,
      properties: %{
        kind: %Schema{type: :string, enum: ["privacy", "consent", "offer", "terms"]},
        updated_at: %Schema{type: :string, format: :"date-time", nullable: true}
      },
      required: [:kind, :updated_at]
    })
  end

  defmodule FranchiseResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "FranchiseResponse",
      type: :object,
      properties: %{
        data: %Schema{
          type: :object,
          properties: %{
            name: %Schema{type: :string, example: "Sushi Like"},
            description: %Schema{type: :string, nullable: true},
            primary_color: %Schema{type: :string, example: "#48010c"},
            dark_primary_color: %Schema{
              type: :string,
              nullable: true,
              example: "#b86a69",
              description: "Цвет для тёмной темы; если пусто, подбирается из основного"
            },
            logo_url: %Schema{type: :string, format: :uri, nullable: true},
            logo_dark_url: %Schema{type: :string, format: :uri, nullable: true},
            legal: Legal,
            address_map: %Schema{
              type: :boolean,
              description: "Адрес выбирается на карте с подсказками DaData"
            },
            client_auth: %Schema{
              type: :boolean,
              description: "Клиенты могут войти по звонку; иначе все заказывают как гости"
            },
            login_call_mode: %Schema{
              type: :string,
              enum: ["inbound", "flash"],
              description: "inbound: клиент звонит сам; flash: клиенту звонят, он вводит 4 цифры"
            },
            rating: %Schema{
              type: :object,
              nullable: true,
              description: "Оценка Яндекса; null, если не настроено или данные старше 7 дней",
              properties: %{
                value: %Schema{type: :number, example: 4.8},
                count: %Schema{type: :integer, example: 120},
                url: %Schema{type: :string, format: :uri, nullable: true}
              },
              required: [:value, :count, :url]
            },
            documents: %Schema{type: :array, items: DocumentSummary}
          },
          required: [
            :name,
            :description,
            :primary_color,
            :dark_primary_color,
            :logo_url,
            :logo_dark_url,
            :address_map,
            :client_auth,
            :login_call_mode,
            :rating,
            :legal,
            :documents
          ]
        }
      },
      required: [:data]
    })
  end

  defmodule DocumentResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "LegalDocumentResponse",
      type: :object,
      properties: %{
        data: %Schema{
          type: :object,
          properties: %{
            kind: %Schema{type: :string, enum: ["privacy", "consent", "offer", "terms"]},
            body: %Schema{type: :string},
            updated_at: %Schema{type: :string, format: :"date-time", nullable: true}
          },
          required: [:kind, :body, :updated_at]
        }
      },
      required: [:data]
    })
  end
end
