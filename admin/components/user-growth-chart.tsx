"use client";

import { useMemo, useState } from "react";
import type { UserGrowthPoint } from "@/lib/admin-data";

type Range = "7d" | "30d";

export function UserGrowthChart({
  sevenDays,
  thirtyDays,
}: {
  sevenDays: UserGrowthPoint[];
  thirtyDays: UserGrowthPoint[];
}) {
  const [range, setRange] = useState<Range>("7d");
  const [hoveredIndex, setHoveredIndex] = useState<number | null>(null);
  const points = range === "7d" ? sevenDays : thirtyDays;
  const width = 760;
  const height = 272;
  const padding = { top: 22, right: 20, bottom: 38, left: 48 };
  const chartWidth = width - padding.left - padding.right;
  const chartHeight = height - padding.top - padding.bottom;
  const rawValues = points.map((point) => point.count);
  const rawMin = Math.min(...rawValues, 0);
  const rawMax = Math.max(...rawValues, 0);
  const minValue = Math.max(0, rawMin - Math.max(1, Math.ceil((rawMax - rawMin) * 0.12)));
  const maxValue = rawMax + Math.max(1, Math.ceil((rawMax - rawMin) * 0.12));
  const valueRange = Math.max(maxValue - minValue, 1);
  const coordinates = points.map((point, index) => ({
    ...point,
    x: padding.left + (points.length === 1 ? chartWidth / 2 : (index / (points.length - 1)) * chartWidth),
    y: padding.top + (1 - (point.count - minValue) / valueRange) * chartHeight,
  }));
  const linePath = smoothPath(coordinates);
  const hoveredPoint = hoveredIndex === null ? null : coordinates[hoveredIndex];
  const periodIncrease = Math.max(0, (points.at(-1)?.count ?? 0) - (points[0]?.count ?? 0));
  const visibleLabels = useMemo(() => {
    if (points.length <= 7) return points.map((_, index) => index);
    return [0, 7, 14, 21, points.length - 1];
  }, [points]);
  const guides = [0, 0.33, 0.66, 1].map((ratio) => ({
    y: padding.top + ratio * chartHeight,
    value: Math.round(maxValue - ratio * valueRange),
  }));

  function chooseRange(nextRange: Range) {
    setRange(nextRange);
    setHoveredIndex(null);
  }

  return (
    <section className="section-card growth-card">
      <div className="growth-card-heading">
        <div>
          <p className="growth-kicker">USER GROWTH</p>
          <h2>ユーザー数の推移</h2>
          <p className="growth-description">登録ユーザーの累計を期間別に確認できます。</p>
        </div>
        <div className="growth-summary">
          <strong>{(points.at(-1)?.count ?? 0).toLocaleString("ja-JP")}</strong>
          <span>累計ユーザー</span>
          <em>期間内 +{periodIncrease}</em>
        </div>
        <div className="chart-range-toggle" role="group" aria-label="グラフの期間">
          <button type="button" className={range === "7d" ? "chart-range-active" : ""} aria-pressed={range === "7d"} onClick={() => chooseRange("7d")}>7日</button>
          <button type="button" className={range === "30d" ? "chart-range-active" : ""} aria-pressed={range === "30d"} onClick={() => chooseRange("30d")}>1ヶ月</button>
        </div>
      </div>

      <div className="growth-chart-wrap">
        <svg viewBox={`0 0 ${width} ${height}`} className="growth-chart" role="img" aria-label={`直近${range === "7d" ? "7日" : "1ヶ月"}のユーザー数推移`} onMouseLeave={() => setHoveredIndex(null)}>
          <title>{`直近${range === "7d" ? "7日" : "1ヶ月"}のユーザー数推移`}</title>
          {guides.map((guide) => (
            <g key={guide.y}>
              <line x1={padding.left} x2={padding.left + chartWidth} y1={guide.y} y2={guide.y} className="chart-guide" />
              <text x={padding.left - 12} y={guide.y + 3} className="chart-axis-label" textAnchor="end">{guide.value}</text>
            </g>
          ))}
          <path d={linePath} className="growth-line" />
          {coordinates.map((point, index) => (
            <g key={point.date} onMouseEnter={() => setHoveredIndex(index)}>
              <circle cx={point.x} cy={point.y} r="16" className="chart-hit-area" />
              {hoveredIndex === index ? <line x1={point.x} x2={point.x} y1={padding.top} y2={padding.top + chartHeight} className="chart-crosshair" /> : null}
              <circle cx={point.x} cy={point.y} r={hoveredIndex === index ? 5 : 2.5} className="growth-point" />
            </g>
          ))}
          {visibleLabels.map((index) => {
            const point = coordinates[index];
            return point ? <text key={point.date} x={point.x} y={height - 12} className="chart-axis-label" textAnchor="middle">{point.label}</text> : null;
          })}
          {hoveredPoint ? (
            <g className="chart-tooltip" transform={`translate(${Math.min(Math.max(hoveredPoint.x - 62, padding.left), width - 132)} ${Math.max(hoveredPoint.y - 68, 8)})`} pointerEvents="none">
              <rect width="124" height="50" rx="7" />
              <text x="12" y="18">{hoveredPoint.label}</text>
              <text x="12" y="37" className="chart-tooltip-value">{hoveredPoint.count.toLocaleString("ja-JP")} ユーザー</text>
            </g>
          ) : null}
        </svg>
      </div>
    </section>
  );
}

function smoothPath(points: Array<{ x: number; y: number }>) {
  if (!points.length) return "M 0 0";
  if (points.length === 1) return `M ${points[0].x} ${points[0].y}`;
  return points.reduce((path, point, index) => {
    if (index === 0) return `M ${point.x} ${point.y}`;
    const previous = points[index - 1];
    const midpointX = (previous.x + point.x) / 2;
    return `${path} C ${midpointX} ${previous.y}, ${midpointX} ${point.y}, ${point.x} ${point.y}`;
  }, "");
}
