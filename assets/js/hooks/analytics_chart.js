import * as echarts from "echarts/core";
import { BarChart, HeatmapChart, LineChart } from "echarts/charts";
import {
  AriaComponent,
  DataZoomComponent,
  GridComponent,
  LegendComponent,
  ToolboxComponent,
  TooltipComponent,
  VisualMapComponent,
} from "echarts/components";
import { CanvasRenderer } from "echarts/renderers";

echarts.use([
  AriaComponent,
  BarChart,
  HeatmapChart,
  CanvasRenderer,
  DataZoomComponent,
  GridComponent,
  LegendComponent,
  LineChart,
  ToolboxComponent,
  TooltipComponent,
  VisualMapComponent,
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
        name: data.kind === "hourly" ? "orders-by-hour" :
          data.kind === "cumulative" ? "revenue-through-day" :
          data.kind === "heatmap" ? "orders-heatmap" :
          data.kind === "ranking" ? "branch-ranking" :
          data.kind === "funnel" ? "order-funnel" :
          data.kind === "delivery" ? "delivery-quality" : `sales-${data.metric}`,
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
      className: "echarts-tooltip",
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
  const comparison = Array.isArray(data.yesterday_orders) && data.yesterday_orders.length === data.hours.length;
  return {
    animation: !matchMedia("(prefers-reduced-motion: reduce)").matches,
    aria: { enabled: true, label: { description: data.title } },
    textStyle: { color: colors.text },
    grid: { left: 10, right: 12, top: comparison ? 62 : 42, bottom: 32, containLabel: true },
    legend: comparison ? { show: true, top: 0, textStyle: { color: colors.text } } : { show: false },
    toolbox: toolbox(data, colors, false),
    tooltip: {
      className: "echarts-tooltip",
      trigger: "axis",
      confine: true,
      backgroundColor: colors.surface,
      textStyle: { color: colors.text },
      formatter(params) {
        const point = params[0];
        if (!point) return "";
        const index = point.dataIndex;
        const today = data.orders[index] == null ? "—" : count(data.orders[index], data.locale);
        const yesterday = comparison ? `<br>${escapeHtml(data.yesterday_label)}: <strong>${escapeHtml(count(data.yesterday_orders[index], data.locale))}</strong>` : "";
        const revenue = data.orders[index] == null ? "" : `<br>${escapeHtml(data.revenue_label)}: ${escapeHtml(data.revenue[index])}`;
        return `${String(data.hours[index]).padStart(2, "0")}:00<br>${escapeHtml(data.today_label || data.orders_label)}: <strong>${escapeHtml(today)}</strong>${revenue}${yesterday}`;
      },
    },
    xAxis: {
      type: "category",
      data: data.hours.map((hour) => `${String(hour).padStart(2, "0")}:00`),
      axisLabel: { interval: 2, color: colors.text, hideOverlap: true },
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
    series: [
      { name: data.today_label || data.orders_label, type: "bar", data: data.orders, color: colors.primary, barMaxWidth: 22 },
      ...(comparison ? [{ name: data.yesterday_label, type: "line", data: data.yesterday_orders,
        color: colors.secondary, showSymbol: false, smooth: true,
        lineStyle: { width: 2, type: "dashed", opacity: 0.65 } }] : []),
    ],
  };
}

function cumulativeOption(data, colors) {
  return {
    animation: !matchMedia("(prefers-reduced-motion: reduce)").matches,
    aria: { enabled: true, label: { description: data.title } },
    textStyle: { color: colors.text },
    grid: { left: 10, right: 12, top: 42, bottom: 32, containLabel: true },
    toolbox: toolbox(data, colors, false),
    tooltip: {
      className: "echarts-tooltip", trigger: "axis", confine: true,
      backgroundColor: colors.surface, textStyle: { color: colors.text },
      formatter(params) {
        const point = params[0];
        if (!point) return "";
        return `${escapeHtml(data.hours[point.dataIndex])}:00<br>${escapeHtml(data.revenue_label)}: <strong>${escapeHtml(money(point.value, data.locale))}</strong>`;
      },
    },
    xAxis: { type: "category", data: data.hours.map(String), axisLabel: { interval: 2, color: colors.text }, axisLine: { lineStyle: { color: colors.grid } }, axisTick: { show: false } },
    yAxis: { type: "value", min: 0, axisLabel: { color: colors.text, formatter: (value) => money(value, data.locale) }, splitLine: { lineStyle: { color: colors.grid } } },
    series: [{ name: data.revenue_label, type: "line", smooth: true, showSymbol: false, data: data.values, color: colors.primary, lineStyle: { width: 2.5 }, areaStyle: { opacity: 0.09 } }],
  };
}

function heatmapOption(data, colors) {
  const max = Math.max(1, ...data.cells.map((cell) => cell.value));
  return {
    animation: !matchMedia("(prefers-reduced-motion: reduce)").matches,
    aria: { enabled: true, label: { description: data.title } },
    textStyle: { color: colors.text },
    grid: { left: 72, right: 18, top: 48, bottom: 70 },
    toolbox: toolbox(data, colors, false),
    tooltip: {
      className: "echarts-tooltip",
      trigger: "item", confine: true, backgroundColor: colors.surface,
      textStyle: { color: colors.text, width: 280, overflow: "break" },
      extraCssText: "max-width: min(320px, 90vw); white-space: normal;",
      formatter({ data: point }) {
        if (!point) return "";
        const end = String((point.hour + 1) % 24).padStart(2, "0");
        const start = String(point.hour).padStart(2, "0");
        return `${escapeHtml(data.days[point.day])} · ${start}:00—${end}:00<br>` +
          `${escapeHtml(data.labels.total)}: <strong>${escapeHtml(count(point.total, data.locale))}</strong><br>` +
          `${escapeHtml(data.labels.dates)}: ${escapeHtml(count(point.dates, data.locale))}<br>` +
          `${escapeHtml(data.labels.average)}: ${escapeHtml(new Intl.NumberFormat(data.locale, { maximumFractionDigits: 2 }).format(point.average))}`;
      },
    },
    xAxis: { type: "category", data: Array.from({ length: 24 }, (_, h) => String(h)),
      axisLabel: { color: colors.text, interval: 2 }, axisLine: { lineStyle: { color: colors.grid } } },
    yAxis: { type: "category", inverse: true, data: data.days,
      axisLabel: { color: colors.text }, axisLine: { lineStyle: { color: colors.grid } } },
    visualMap: { min: 0, max, calculable: true, orient: "horizontal", left: "center", bottom: 4,
      text: [data.labels.scale, "0"], textStyle: { color: colors.text },
      inRange: { color: [colors.surface, colors.primary] } },
    series: [{ type: "heatmap", data: data.cells.map((cell) => ({
      ...cell, average: cell.value, value: [cell.hour, cell.day, cell.value],
    })), emphasis: { itemStyle: { borderColor: colors.text, borderWidth: 1 } } }],
  };
}

function rankingOption(data, colors) {
  return {
    animation: !matchMedia("(prefers-reduced-motion: reduce)").matches,
    aria: { enabled: true, label: { description: data.title } },
    textStyle: { color: colors.text },
    grid: { left: 12, right: 24, top: 45, bottom: 20, containLabel: true },
    toolbox: toolbox(data, colors, false),
    tooltip: {
      className: "echarts-tooltip",
      trigger: "item", confine: true, backgroundColor: colors.surface,
      textStyle: { color: colors.text },
      extraCssText: "max-width: min(320px, 90vw); white-space: normal;",
      formatter({ dataIndex }) {
        const row = data.rows[dataIndex];
        if (!row) return "";
        const value = row.value == null ? "—" : data.metric === "orders_per_day"
          ? new Intl.NumberFormat(data.locale, { maximumFractionDigits: 2 }).format(row.value)
          : money(row.value, data.locale);
        return `${escapeHtml(row.name)}: <strong>${escapeHtml(value)}</strong><br>` +
          `${escapeHtml(data.labels.period)}: ${escapeHtml(data.period)}<br>` +
          `${escapeHtml(data.labels.completed)}: ${escapeHtml(count(row.completed, data.locale))}<br>` +
          `${escapeHtml(data.labels.calendar_days)}: ${escapeHtml(count(row.days, data.locale))}`;
      },
    },
    xAxis: { type: "value", axisLabel: { color: colors.text,
      formatter: (v) => data.metric === "orders_per_day" ? count(v, data.locale) : money(v, data.locale) },
    splitLine: { lineStyle: { color: colors.grid } } },
    yAxis: { type: "category", inverse: true, data: data.rows.map((row) => row.name),
      axisLabel: { color: colors.text, width: 110, overflow: "truncate" } },
    series: [{ type: "bar", data: data.rows.map((row) => row.value), color: colors.primary, barMaxWidth: 26 }],
  };
}

function funnelOption(data, colors) {
  return {
    animation: !matchMedia("(prefers-reduced-motion: reduce)").matches,
    aria: { enabled: true, label: { description: data.title } },
    textStyle: { color: colors.text },
    grid: { left: 8, right: 24, top: 44, bottom: 28, containLabel: true },
    toolbox: toolbox(data, colors, false),
    tooltip: {
      className: "echarts-tooltip",
      trigger: "item", confine: true, backgroundColor: colors.surface,
      textStyle: { color: colors.text },
      extraCssText: "max-width: min(320px, 90vw); white-space: normal;",
      formatter({ dataIndex }) {
        const stage = data.stages[dataIndex];
        if (!stage) return "";
        const percentage = (value) => value == null ? "—" : `${count(value, data.locale)}%`;
        return `<strong>${escapeHtml(stage.name)}</strong>: ${escapeHtml(count(stage.sessions, data.locale))}<br>` +
          `${escapeHtml(data.labels.previous)}: ${escapeHtml(percentage(stage.previous))}<br>` +
          `${escapeHtml(data.labels.start)}: ${escapeHtml(percentage(stage.start))}<br>` +
          `${escapeHtml(data.labels.lost)}: ${stage.lost == null ? "—" : escapeHtml(count(stage.lost, data.locale))}`;
      },
    },
    xAxis: { type: "value", min: 0, minInterval: 1,
      axisLabel: { color: colors.text, formatter: (value) => count(value, data.locale) },
      splitLine: { lineStyle: { color: colors.grid } } },
    yAxis: { type: "category", inverse: true, data: data.stages.map((stage) => stage.name),
      axisLabel: { color: colors.text, width: 120, overflow: "truncate" } },
    series: [{ type: "bar", data: data.stages.map((stage) => stage.sessions),
      color: colors.primary, barMaxWidth: 28 }],
  };
}

function deliveryOption(data, colors) {
  const series = [
    { name: data.labels.on_time_rate, key: "on_time_rate", color: colors.primary },
    { name: data.labels.coverage, key: "coverage", color: colors.secondary },
  ];
  const zoomable = data.days.length > 14;
  return {
    animation: !matchMedia("(prefers-reduced-motion: reduce)").matches,
    aria: { enabled: true, label: { description: data.title } },
    textStyle: { color: colors.text },
    grid: { left: 12, right: 12, top: 90, bottom: zoomable ? 70 : 38, containLabel: true },
    legend: { show: true, left: 8, top: 8, right: 8, textStyle: { color: colors.text } },
    toolbox: toolbox(data, colors, true, 51),
    tooltip: {
      className: "echarts-tooltip",
      trigger: "axis", confine: true, backgroundColor: colors.surface,
      textStyle: { color: colors.text },
      extraCssText: "max-width: min(320px, 90vw); white-space: normal;",
      formatter(params) {
        const day = data.days[params[0]?.dataIndex];
        if (!day) return "";
        const percentage = (value) => value == null ? "—" : `${count(value, data.locale)}%`;
        return `<strong>${escapeHtml(day.date)}</strong><br>` +
          `${escapeHtml(data.labels.on_time_rate)}: ${escapeHtml(percentage(day.on_time_rate))}<br>` +
          `${escapeHtml(data.labels.coverage)}: ${escapeHtml(percentage(day.coverage))}<br>` +
          `${escapeHtml(data.labels.measured)}: ${escapeHtml(count(day.measured, data.locale))}/${escapeHtml(count(day.total, data.locale))}<br>` +
          `${escapeHtml(data.labels.late)}: ${escapeHtml(count(day.late, data.locale))}`;
      },
    },
    xAxis: { type: "category", data: data.days.map((day) => day.date.slice(5)),
      axisLabel: { color: colors.text, hideOverlap: true },
      axisLine: { lineStyle: { color: colors.grid } } },
    yAxis: { type: "value", min: 0, max: 100,
      axisLabel: { color: colors.text, formatter: "{value}%" },
      splitLine: { lineStyle: { color: colors.grid } } },
    dataZoom: zoomable ? [
      { type: "inside", xAxisIndex: 0, zoomOnMouseWheel: false, moveOnMouseWheel: false, moveOnMouseMove: true },
      { type: "slider", xAxisIndex: 0, bottom: 8, height: 18,
        borderColor: colors.grid,
        fillerColor: colors.primary.replace("rgb(", "rgba(").replace(")", ", 0.16)"),
      },
    ] : [],
    series: series.map(({ name, key, color }, index) => ({
      name, type: "line", color, symbol: index === 0 ? "circle" : "diamond",
      lineStyle: { width: 2.5, type: index === 0 ? "solid" : "dashed" },
      showSymbol: data.days.length <= 24, connectNulls: false,
      data: data.days.map((day) => ({ value: day[key], date: day.date })),
    })),
  };
}

function options(data) {
  const colors = palette();
  if (data.kind === "sales") return salesOption(data, colors);
  if (data.kind === "hourly") return hourlyOption(data, colors);
  if (data.kind === "cumulative") return cumulativeOption(data, colors);
  if (data.kind === "heatmap") return heatmapOption(data, colors);
  if (data.kind === "ranking") return rankingOption(data, colors);
  if (data.kind === "funnel") return funnelOption(data, colors);
  if (data.kind === "delivery") return deliveryOption(data, colors);
  throw new Error(`Unsupported analytics chart kind: ${data.kind}`);
}

export const AnalyticsChart = {
  mounted() {
    this.surface = this.el.querySelector(`[id="${this.el.id}-plot"]`);
    this.chart = echarts.init(this.surface, null, { renderer: "canvas" });
    this.chart.on("click", ({ data }) => {
      if (data?.day !== undefined && data?.hour !== undefined) {
        const payload = { day: data.day + 1, hour: data.hour };
        this.pushEvent("heatmap_detail", payload);
      }
      if (typeof data?.date === "string") this.pushEvent("delivery_day_detail", { day: data.date });
    });
    this.chart.on("click", ({ dataIndex, seriesIndex }) => {
      const chartData = JSON.parse(this.el.dataset.chart);
      if (chartData.kind === "hourly" && chartData.drilldown && seriesIndex === 0 &&
          Number.isInteger(dataIndex) && chartData.orders[dataIndex] != null) {
        this.pushEvent("dashboard_hour", { hour: chartData.hours[dataIndex] });
      }
    });
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
    }) : data.kind === "delivery" ? JSON.stringify(data.days.map((day) => day.date)) : null;
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
