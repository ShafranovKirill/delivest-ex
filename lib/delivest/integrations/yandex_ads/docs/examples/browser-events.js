// Синтетический пример, не подключен к bundle и не исполнялся на сайте.
// https://yandex.ru/support/metrica/ru/code/counter-spa-setup
// https://yandex.ru/support/metrica/ru/ecommerce/data
// https://yandex.ru/support/metrica/ru/objects/get-client-id
// Реальная инициализация требует согласия на сбор данных и установленного тега.

const counterId = 12345678;
window.dataLayer = window.dataLayer || [];

ym(counterId, "init", {
  defer: true,
  webvisor: false,
  ecommerce: "dataLayer"
});

// Вызывать только после разрешения сбора и на реальном маршруте SPA.
ym(counterId, "getClientID", (clientId) => {
  // Передать строку clientId серверу по защищенному каналу; не в URL и не в лог.
  void clientId;
});
ym(counterId, "hit", "https://example.invalid/menu?product=pizza-primer");

const product = {id: "offer-synthetic-7", name: "Пицца Пример", price: 1250, quantity: 1};
window.dataLayer.push({ecommerce: {currencyCode: "RUB", detail: {products: [product]}}});
window.dataLayer.push({ecommerce: {currencyCode: "RUB", add: {products: [product]}}});
window.dataLayer.push({ecommerce: {currencyCode: "RUB", remove: {products: [product]}}});

// purchase и completed формируются по подтвержденному серверному событию.
