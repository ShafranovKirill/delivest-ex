%{
  "advertising_live/index.ex" =>
    {"lib/delivest/advertising/link.ex", "Marketing / advertising links",
     "advertising_live/index.ex"},
  "auth_live/login.ex" =>
    {"staff login form in AuthLive.Login", "Staff authentication", "auth_live/login.ex"},
  "branch_live/branch_form_component.ex" =>
    {"lib/delivest_web/live/staff/branch_live/branch_form.ex", "Settings / Branch operations",
     "branch_live/branch_form_component.ex"},
  "branch_live/edit.ex" =>
    {"branch deletion confirmation parameter", "Settings / Branches", "branch_live/edit.ex"},
  "branch_live/location_fields.ex" =>
    {"lib/delivest_web/live/staff/branch_live/branch_form.ex",
     "Settings / Branch operations / Location", "branch_live/branch_form_component.ex"},
  "branch_live/special_hours_component.ex" =>
    {"branch special-hours operation", "Settings / Branch operations / Schedule",
     "branch_live/special_hours_component.ex"},
  "branch_live/working_hours_component.ex" =>
    {"lib/delivest_web/live/staff/branch_live/branch_form.ex",
     "Settings / Branch operations / Schedule", "branch_live/branch_form_component.ex"},
  "category_live/category_form_component.ex" =>
    {"lib/delivest/net/category.ex", "Menu / Categories",
     "category_live/category_form_component.ex"},
  "client_live/client_form_component.ex" =>
    {"lib/delivest/identity/client.ex", "Clients / Client",
     "client_live/client_form_component.ex"},
  "client_live/client_codes_component.ex" =>
    {"Delivest.Promo code issuance operation", "Clients / Client / Promo codes",
     "client_live/client_codes_component.ex"},
  "client_live/clients.ex" =>
    {"client list search and status filters", "Clients / List", "client_live/clients.ex"},
  "client_live/show.ex" =>
    {"client loyalty adjustment and card operations", "Clients / Client", "client_live/show.ex"},
  "delivery_live/address.ex" =>
    {"Delivest.Delivery address operation", "Settings / Delivery / Address",
     "delivery_live/address.ex"},
  "delivery_live/couriers.ex" =>
    {"courier list search/source filters", "Delivery / Couriers", "delivery_live/couriers.ex"},
  "delivery_live/zone_panel.ex" =>
    {"lib/delivest/delivery/zone.ex", "Settings / Delivery / Zones", "delivery_live/zones.ex"},
  "delivery_live/zones.ex" =>
    {"lib/delivest/delivery/settings.ex", "Settings / Delivery / Zones", "delivery_live/zones.ex"},
  "finance_live/payments.ex" =>
    {"lib/delivest/identity/branch/payment_settings.ex", "Settings / Orders and payment",
     "finance_live/payments.ex"},
  "finance_live/transactions.ex" =>
    {"payment register filters", "Finance / Transactions", "finance_live/transactions.ex"},
  "franchise_live/settings_form_component.ex" =>
    {"lib/delivest/franchise/settings.ex", "Settings / Network and brand",
     "franchise_live/settings_form_component.ex"},
  "franchise_live/document_form_component.ex" =>
    {"Franchise document body operation", "Settings / Network and brand / Documents",
     "franchise_live/document_form_component.ex"},
  "franchise_live/index.ex" =>
    {"franchise dangerous-action confirmation parameter", "Settings / Network and brand",
     "franchise_live/index.ex"},
  "integration_live/dadata.ex" =>
    {"lib/delivest/integrations/dadata/settings.ex", "Settings / Integrations / Dadata",
     "integration_live/dadata.ex"},
  "integration_live/fiscal.ex" =>
    {"lib/delivest/fiscal/branch_settings.ex", "Settings / Integrations / Fiscal",
     "integration_live/fiscal.ex"},
  "integration_live/frontpad.ex" =>
    {"lib/delivest/integrations/crm/branch_settings.ex", "Settings / Integrations / Frontpad",
     "integration_live/frontpad.ex"},
  "integration_live/iiko.ex" =>
    {"lib/delivest/integrations/crm/branch_settings.ex", "Settings / Integrations / Iiko",
     "integration_live/iiko.ex"},
  "integration_live/index.ex" =>
    {"integration capability toggle operations", "Settings / Features and connections",
     "integration_live/index.ex"},
  "integration_live/rkeeper.ex" =>
    {"lib/delivest/integrations/crm/branch_settings.ex", "Settings / Integrations / Rkeeper",
     "integration_live/rkeeper.ex"},
  "integration_live/yandex_delivery.ex" =>
    {"lib/delivest/integrations/yandex_delivery/settings.ex",
     "Settings / Integrations / Yandex Delivery", "integration_live/yandex_delivery.ex"},
  "integration_live/yandex_eda.ex" =>
    {"lib/delivest/integrations/yandex_eda/branch_settings.ex",
     "Settings / Integrations / Yandex Eda", "integration_live/yandex_eda.ex"},
  "integration_live/yandex_eda_access.ex" =>
    {"lib/delivest/integrations/yandex_eda/settings.ex",
     "Settings / Integrations / Yandex Eda shared", "integration_live/yandex_eda_access.ex"},
  "integration_live/yandex_eda_menu.ex" =>
    {"Yandex Eda per-product menu capability operation",
     "Settings / Integrations / Yandex Eda menu", "integration_live/yandex_eda_menu.ex"},
  "integration_live/yandex_eda_pause.ex" =>
    {"Yandex Eda pause operation", "Settings / Integrations / Yandex Eda",
     "integration_live/yandex_eda_pause.ex"},
  "integration_live/yandex_eda_reconciliation.ex" =>
    {"Yandex Eda reconciliation date filter", "Settings / Integrations / Yandex Eda",
     "integration_live/yandex_eda_reconciliation.ex"},
  "integration_live/ycart.ex" =>
    {"lib/delivest/identity/branch/ycart_settings.ex", "Settings / Integrations / Ycart",
     "integration_live/ycart.ex"},
  "integration_live/yookassa.ex" =>
    {"lib/delivest/integrations/yookassa/settings.ex", "Settings / Integrations / Yookassa",
     "integration_live/yookassa.ex"},
  "integration_live/zvonok.ex" =>
    {"lib/delivest/integrations/zvonok/settings.ex", "Settings / Integrations / Zvonok",
     "integration_live/zvonok.ex"},
  "loyalty_live/index.ex" =>
    {"lib/delivest/identity/branch/loyalty_settings.ex", "Settings / Loyalty / Branch",
     "loyalty_live/index.ex"},
  "log_live/index.ex" =>
    {"system log query filters", "Settings / Data and system / Logs", "log_live/index.ex"},
  "marketing_live/bonus_settings_component.ex" =>
    {"lib/delivest/franchise/settings.ex", "Settings / Loyalty / Network",
     "marketing_live/bonus_settings_component.ex"},
  "marketing_live/index.ex" =>
    {"lib/delivest/marketing/policy.ex", "Marketing / Policies", "marketing_live/index.ex"},
  "menu_live/popular.ex" =>
    {"lib/delivest/popular/settings.ex", "Menu / Popular", "menu_live/popular.ex"},
  "order_live/components/client_panel.ex" =>
    {"Delivest.Oms order client picker", "Orders / Order",
     "order_live/components/client_panel.ex"},
  "order_live/components/cancel_order_modal.ex" =>
    {"order cancellation parameters", "Orders / Order",
     "order_live/components/cancel_order_modal.ex"},
  "order_live/components/cart_component.ex" =>
    {"order promo code application parameter", "Orders / Order",
     "order_live/components/cart_component.ex"},
  "order_live/components/catalog_component.ex" =>
    {"order product catalog search", "Orders / Order",
     "order_live/components/catalog_component.ex"},
  "order_live/components/details_component.ex" =>
    {"lib/delivest/oms/order.ex", "Orders / Order", "order_live/components/details_component.ex"},
  "order_live/components/intake_controls.ex" =>
    {"order intake pause/resume scope and duration", "Settings / Orders and payment",
     "order_live/components/intake_controls.ex"},
  "order_live/components/order_card_component.ex" =>
    {"order card confirmation/payment operations", "Orders / Order",
     "order_live/components/order_card_component.ex"},
  "order_live/components/orders_toolbar.ex" =>
    {"order queue search/date/status filters", "Orders / Queue",
     "order_live/components/orders_toolbar.ex"},
  "order_live/components/revert_status_modal.ex" =>
    {"order status reversal reason", "Orders / Order",
     "order_live/components/revert_status_modal.ex"},
  "order_live/components/segmented.ex" =>
    {"segmented control caller-provided parameter", "Orders / Order",
     "order_live/components/segmented.ex"},
  "order_live/order_form.ex" =>
    {"lib/delivest/oms/order.ex", "Orders / Order", "order_live/order_form.ex"},
  "pos_live/index.ex" =>
    {"POS search, modifier selection, promo and payment parameters", "Orders / POS",
     "pos_live/index.ex"},
  "product_live/branch_products.ex" =>
    {"branch product list search/filter", "Menu / Products", "product_live/branch_products.ex"},
  "product_live/bulk.ex" =>
    {"bulk product row field operation", "Menu / Products / Bulk edit", "product_live/bulk.ex"},
  "product_live/modifiers.ex" =>
    {"modifier external article edit parameter", "Menu / Modifiers", "product_live/modifiers.ex"},
  "product_live/operations.ex" =>
    {"product operation target/choice parameters", "Menu / Product operations",
     "product_live/operations.ex"},
  "product_live/product_picker.ex" =>
    {"product picker search/selection state", "Menu / Products", "product_live/product_picker.ex"},
  "product_live/product_tags.ex" =>
    {"product tags multiselect bound to caller form field", "Menu / Product",
     "product_live/product_form_component.ex"},
  "product_live/product_form_component.ex" =>
    {"lib/delivest/net/product.ex", "Menu / Product", "product_live/product_form_component.ex"},
  "product_live/products.ex" =>
    {"product list search/category/status and selected IDs", "Menu / Products",
     "product_live/products.ex"},
  "product_live/stop_list.ex" =>
    {"stock stop list search filters", "Menu / Stock stops", "product_live/stop_list.ex"},
  "product_live/tags.ex" =>
    {"lib/delivest/net/product_tag.ex", "Menu / Tags", "product_live/tags.ex"},
  "promotion_live/issued_codes_component.ex" =>
    {"Delivest.Promo code issuance parameters", "Marketing / Promotions / Codes",
     "promotion_live/issued_codes_component.ex"},
  "promotion_live/product_sale_form_component.ex" =>
    {"lib/delivest/promo/promotion.ex", "Marketing / Promotions",
     "promotion_live/product_sale_form_component.ex"},
  "promotion_live/promotion_form_component.ex" =>
    {"lib/delivest/promo/promotion.ex", "Marketing / Promotions",
     "promotion_live/promotion_form_component.ex"},
  "receipt_live/index.ex" =>
    {"fiscal receipt register filters", "Finance / Receipts", "receipt_live/index.ex"},
  "role_live/role_form_component.ex" =>
    {"lib/delivest/identity/role.ex", "Settings / Team and access / Roles",
     "role_live/role_form_component.ex"},
  "segment_live/index.ex" =>
    {"lib/delivest/segments/segment.ex", "Clients / Segments", "segment_live/index.ex"},
  "staff_live/staff_form_component.ex" =>
    {"lib/delivest/identity/staff.ex", "Settings / Team and access / Staff",
     "staff_live/staff_form_component.ex"},
  "staff_live/staffs.ex" =>
    {"staff list search filter", "Settings / Team and access / Staff", "staff_live/staffs.ex"},
  "statistics_live/index.ex" =>
    {"Delivest.Analytics report filters", "Analytics", "statistics_live/index.ex"},
  "stock_live/stock_form_component.ex" =>
    {"lib/delivest/net/stock.ex", "Marketing / Banners", "stock_live/stock_form_component.ex"}
}
