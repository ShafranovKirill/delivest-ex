import * as echarts from "echarts/core";
import { BarChart, LineChart } from "echarts/charts";
import {
  AriaComponent,
  DataZoomComponent,
  GridComponent,
  LegendComponent,
  ToolboxComponent,
  TooltipComponent,
} from "echarts/components";
import { CanvasRenderer } from "echarts/renderers";

echarts.use([
  AriaComponent,
  BarChart,
  CanvasRenderer,
  DataZoomComponent,
  GridComponent,
  LegendComponent,
  LineChart,
  ToolboxComponent,
  TooltipComponent,
]);

const escapeHtml = (value) => String(value).replace(/[&<>"']/g, (character) => ({
  "&": "&amp;",
  "<": "&lt;",
  ">": "&gt;",
  '"': "&quot;",
  "'": "&#39;",
})[character]);

const rgbColor = (value) => {
  const canvas = document.createElement("canvas");
  canvas.width = canvas.height = 1;
  const context = canvas.getContext("2d");
  context.fillStyle = value;
  context.fillRect(0, 0, 1, 1);
  const { data } = context.getImageData(0, 0, 1, 1);
  return `rgb(${data[0]}, ${data[1]}, ${data[2]})`;
};

const palette = () => {
  const css = getComputedStyle(document.documentElement);
  return {
    primary: rgbColor(css.getPropertyValue("--color-primary").trim()),
    secondary: rgbColor(css.getPropertyValue("--color-secondary").trim()),
    text: rgbColor(css.getPropertyValue("--color-base-content").trim()),
    grid: rgbColor(css.getPropertyValue("--color-base-300").trim()),
    surface: rgbColor(css.getPropertyValue("--color-base-100").trim()),
  };
};

const language = (locale) => String(locale).toLowerCase().startsWith("ru") ? {
  image: "Сохранить PNG",
  restore: "Сбросить масштаб",
  zoom: "Масштаб",
  back: "Назад",
} : {
  image: "Save PNG",
  restore: "Reset zoom",
  zoom: "Zoom",
  back: "Back",
};

const money = (value, locale) => `${new Intl.NumberFormat(locale, {
  minimumFractionDigits: Number.isInteger(value / 100) ? 0 : 2,
  maximumFractionDigits: 2,
}).format(value / 100)} ₽`;

const count = (value, locale) => new Intl.NumberFormat(locale).format(value);

function toolbox(data, colors, zoomable, top = 0) {
  const labels = language(data.locale);
  return {
    show: true,
    right: 4,
    top,
    iconStyle: { borderColor: colors.text },
    emphasis: { iconStyle: { borderColor: colors.primary } },
    feature: {
      ...(zoomable ? {
        dataZoom: { title: { zoom: labels.zoom, back: labels.back }, yAxisIndex: "none" },
        restore: { title: labels.restore },
      } : {}),
      saveAsImage: {
        title: labels.image,
        name: data.kind === "products" ? "best-sellers" : data.kind === "hourly" ? "orders-by-hour" : `sales-${data.metric}`,
        backgroundColor: colors.surface,
        pixelRatio: 2,
      },
    },
  };
}

function salesOption(data, colors) {
  const comparison = data.previous.length > 0;
  const series = [data.current, ...(comparison ? [data.previous] : [])].map((points, index) => ({
    name: index === 0 ? data.selected : data.comparison,
    type: data.metric === "orders" ? "bar" : "line",
    data: points.map((point) => point ? { value: point.value, range: point.range } : null),
    color: index === 0 ? colors.primary : colors.secondary,
    showSymbol: points.length <= 24,
    symbol: index === 0 ? "circle" : "diamond",
    symbolSize: 7,
    lineStyle: { width: 2.5, type: index === 0 ? "solid" : "dashed" },
    barMaxWidth: 24,
    emphasis: { focus: "series" },
  }));
  const zoomable = data.labels.length > 14;
  return {
    animation: !matchMedia("(prefers-reduced-motion: reduce)").matches,
    aria: { enabled: true, label: { description: data.title }, decal: { show: comparison } },
    color: [colors.primary, colors.secondary],
    textStyle: { color: colors.text },
    grid: { left: 12, right: 12, top: comparison ? 91 : 48, bottom: zoomable ? 72 : 38, containLabel: true },
    legend: comparison ? { show: true, left: 8, top: 8, right: 8, textStyle: { color: colors.text } } : { show: false },
    toolbox: toolbox(data, colors, true, comparison ? 51 : 0),
    tooltip: {
      trigger: "axis",
      confine: true,
      backgroundColor: colors.surface,
      textStyle: { color: colors.text },
      formatter(params) {
        const items = params.filter((item) => item.data && Number.isFinite(item.data.value));
        if (items.length === 0) return "";
        const lines = items.map((item) => {
          const value = data.metric === "orders" ? count(item.data.value, data.locale) : money(item.data.value, data.locale);
          return `${escapeHtml(item.seriesName)} · ${escapeHtml(item.data.range)}: <strong>${escapeHtml(value)}</strong>`;
        });
        if (comparison) {
          const index = params[0].dataIndex;
          if (!data.current[index]) lines.push(`${escapeHtml(data.selected)}: —`);
          if (!data.previous[index]) lines.push(`${escapeHtml(data.comparison)}: —`);
        }
        return lines.join("<br>");
      },
    },
    xAxis: {
      type: "category",
      data: data.labels,
      boundaryGap: data.metric === "orders",
      axisLine: { lineStyle: { color: colors.grid } },
      axisTick: { show: false },
      axisLabel: { color: colors.text, hideOverlap: true },
    },
    yAxis: {
      type: "value",
      minInterval: data.metric === "orders" ? 1 : undefined,
      axisLabel: {
        color: colors.text,
        formatter: (value) => data.metric === "orders" ? count(value, data.locale) : money(value, data.locale),
      },
      splitLine: { lineStyle: { color: colors.grid } },
    },
    dataZoom: zoomable ? [
      { type: "inside", xAxisIndex: 0, zoomOnMouseWheel: false, moveOnMouseWheel: false, moveOnMouseMove: true },
      {
        type: "slider", xAxisIndex: 0, bottom: 8, height: 18,
        borderColor: colors.grid,
        fillerColor: colors.primary.replace("rgb(", "rgba(").replace(")", ", 0.16)"),
      },
    ] : [],
    series,
  };
}

function hourlyOption(data, colors) {
  return {
    animation: !matchMedia("(prefers-reduced-motion: reduce)").matches,
    aria: { enabled: true, label: { description: data.title } },
    textStyle: { color: colors.text },
    grid: { left: 10, right: 12, top: 42, bottom: 32, containLabel: true },
    toolbox: toolbox(data, colors, false),
    tooltip: {
      trigger: "axis",
      confine: true,
      backgroundColor: colors.surface,
      textStyle: { color: colors.text },
      formatter(params) {
        const point = params[0];
        if (!point) return "";
        const index = point.dataIndex;
        return `${escapeHtml(data.hours[index])}:00<br>${escapeHtml(data.orders_label)}: <strong>${escapeHtml(count(data.orders[index], data.locale))}</strong><br>${escapeHtml(data.revenue_label)}: ${escapeHtml(data.revenue[index])}`;
      },
    },
    xAxis: {
      type: "category",
      data: data.hours.map((hour) => String(hour)),
      axisLabel: { interval: 2, color: colors.text },
      axisLine: { lineStyle: { color: colors.grid } },
      axisTick: { show: false },
    },
    yAxis: {
      type: "value",
      min: 0,
      minInterval: 1,
      axisLabel: { color: colors.text, formatter: (value) => count(value, data.locale) },
      splitLine: { lineStyle: { color: colors.grid } },
    },
    series: [{ name: data.orders_label, type: "bar", data: data.orders, color: colors.primary, barMaxWidth: 22 }],
  };
}

function productsOption(data, colors) {
  return {
    animation: !matchMedia("(prefers-reduced-motion: reduce)").matches,
    aria: { enabled: true, label: { description: data.title } },
    textStyle: { color: colors.text },
    grid: { left: 12, right: 32, top: 42, bottom: 25, containLabel: true },
    toolbox: toolbox(data, colors, false),
    tooltip: {
      trigger: "item",
      confine: true,
      backgroundColor: colors.surface,
      textStyle: { color: colors.text },
      formatter(params) {
        const product = data.products[params.dataIndex];
        if (!product) return "";
        return `<strong>${escapeHtml(product.name)}</strong><br>${escapeHtml(data.share_label)}: ${escapeHtml(count(product.share, data.locale))}%<br>${escapeHtml(data.quantity_label)}: ${escapeHtml(count(product.quantity, data.locale))}<br>${escapeHtml(data.revenue_label)}: ${escapeHtml(product.revenue)}`;
      },
    },
    xAxis: {
      type: "value",
      min: 0,
      max: 100,
      axisLabel: { color: colors.text, formatter: "{value}%" },
      splitLine: { lineStyle: { color: colors.grid } },
    },
    yAxis: {
      type: "category",
      inverse: true,
      data: data.products.map((product) => product.name),
      axisLabel: { color: colors.text, width: 105, overflow: "truncate" },
      axisLine: { lineStyle: { color: colors.grid } },
      axisTick: { show: false },
    },
    series: [{ name: data.share_label, type: "bar", data: data.products.map((product) => product.share), color: colors.primary, barMaxWidth: 24 }],
  };
}

function options(data) {
  const colors = palette();
  if (data.kind === "sales") return salesOption(data, colors);
  if (data.kind === "hourly") return hourlyOption(data, colors);
  return productsOption(data, colors);
}

export const AnalyticsChart = {
  mounted() {
    this.surface = this.el.querySelector(`[id="${this.el.id}-plot"]`);
    this.chart = echarts.init(this.surface, null, { renderer: "canvas" });
    this.renderChart();
    this.resizeObserver = new ResizeObserver(() => this.chart.resize());
    this.resizeObserver.observe(this.el);
    this.themeObserver = new MutationObserver(() => this.renderChart());
    this.themeObserver.observe(document.documentElement, { attributes: true, attributeFilter: ["data-theme"] });
    this.colorScheme = matchMedia("(prefers-color-scheme: dark)");
    this.onColorScheme = () => this.renderChart();
    this.colorScheme.addEventListener("change", this.onColorScheme);
  },
  updated() {
    this.renderChart();
  },
  destroyed() {
    this.resizeObserver.disconnect();
    this.themeObserver.disconnect();
    this.colorScheme.removeEventListener("change", this.onColorScheme);
    this.chart.dispose();
  },
  renderChart() {
    const data = JSON.parse(this.el.dataset.chart);
    const labels = data.kind === "sales" ? JSON.stringify({
      labels: data.labels,
      current: data.current.map((point) => point.range),
      previous: data.previous.map((point) => point.range),
    }) : null;
    const oldOption = this.chart.getOption();
    const oldZoom = labels === this.labels && oldOption.dataZoom?.[0];
    const oldLegend = labels === this.labels && oldOption.legend?.[0]?.selected;
    const next = options(data);
    this.chart.setOption(next, { notMerge: true });
    if (oldZoom && next.dataZoom?.length) {
      this.chart.dispatchAction({ type: "dataZoom", start: oldZoom.start, end: oldZoom.end });
    }
    if (oldLegend && next.legend?.show) {
      Object.entries(oldLegend).forEach(([name, selected]) => {
        if (selected === false) this.chart.dispatchAction({ type: "legendUnSelect", name });
      });
    }
    this.labels = labels;
    this.chart.resize();
  },
};
