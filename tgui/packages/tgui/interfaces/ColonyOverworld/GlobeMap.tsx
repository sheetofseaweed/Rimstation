import { useEffect, useLayoutEffect, useMemo, useRef } from 'react';
import { Box, Button } from 'tgui-core/components';

import {
  GLOBE_ARC,
  flatToSphere,
  GLOBE_PALETTE,
  hexFlat,
  type Mat3,
  packCellTexture,
  type RegionFrame,
  regionFitZoom,
  regionFrame,
  sunDirection,
  toView,
  type Vec3,
  viewFacing,
  viewRotation,
} from './globeGeometry';
import { GLOBE_FRAGMENT_SHADER, GLOBE_VERTEX_SHADER } from './globeShader';
import { parseCellId } from './hexGeometry';
import type { KnownCell, KnownSite, RegionMapProps } from './RegionMap';

export type GlobeQuality = 'full' | 'light';

export type PlanetInfo = {
  seed: number;
  temperature_c: number;
  moisture: number;
};

/** The colony's clock: 0 midnight, 0.5 noon, and how long a day lasts in deciseconds. */
export type SunInfo = { fraction: number; day_length: number };

type Props = RegionMapProps & {
  planet?: PlanetInfo | null;
  sun?: SunInfo | null;
  quality: GlobeQuality;
  /** Reported after a timing run: median milliseconds to draw one frame at this quality. */
  onFrameTime?: (ms: number, quality: GlobeQuality) => void;
  /** Reported when WebGL turns out to be unusable, so the caller can show the flat map. */
  onFailure?: () => void;
};

/** Canvas pixels per screen pixel, per quality. Never above 1, whatever the screen's density. */
const QUALITY_SCALE: Record<GlobeQuality, number> = { full: 1, light: 0.6 };
/** Milliseconds between cloud frames in full quality, and between sun updates in light quality. */
const CLOUD_FRAME_MS = 100;
const SUN_FRAME_MS = 5000;
const DRAG_THRESHOLD_PIXELS = 4;
const ZOOM_STEP = 1.2;
const MIN_ZOOM = 0.38;
/** Below this many pixels per hex, outlines and marks are hidden: they would be noise. */
const MIN_HEX_PIXELS = 4;

let webglChecked: boolean | null = null;

/** TRUE when this browser can draw the globe. Checked once. */
export function isWebGLAvailable(): boolean {
  if (webglChecked === null) {
    try {
      const probe = document.createElement('canvas');
      webglChecked = !!probe.getContext('webgl');
    } catch {
      webglChecked = false;
    }
  }
  return webglChecked;
}

const smoothstep = (edge0: number, edge1: number, x: number) => {
  const t = Math.max(0, Math.min(1, (x - edge0) / (edge1 - edge0)));
  return t * t * (3 - 2 * t);
};

/** Owns the WebGL program and textures. Plain class: React only decides when to draw. */
class GlobeRenderer {
  gl: WebGLRenderingContext;
  program: WebGLProgram;
  locations: Record<string, WebGLUniformLocation | null> = {};
  cellTexture: WebGLTexture;
  paletteTexture: WebGLTexture;
  cellsSize = 1;
  cellsOffset = 0;

  constructor(gl: WebGLRenderingContext) {
    this.gl = gl;
    this.program = this.link();
    gl.useProgram(this.program);

    const buffer = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
    gl.bufferData(
      gl.ARRAY_BUFFER,
      new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]),
      gl.STATIC_DRAW,
    );
    const position = gl.getAttribLocation(this.program, 'aPosition');
    gl.enableVertexAttribArray(position);
    gl.vertexAttribPointer(position, 2, gl.FLOAT, false, 0, 0);

    for (const name of [
      'uResolution',
      'uRotation',
      'uRadius',
      'uTime',
      'uSun',
      'uSunView',
      'uSeed',
      'uHome',
      'uEast',
      'uNorth',
      'uArc',
      'uRegionRadius',
      'uCells',
      'uCellsSize',
      'uCellsOffset',
      'uPalette',
      'uTemperature',
      'uWetness',
      'uCloudOpacity',
      'uCloudShadows',
      'uNightFloor',
    ]) {
      this.locations[name] = gl.getUniformLocation(this.program, name);
    }

    this.cellTexture = this.makeTexture();
    this.paletteTexture = this.makeTexture();
    const palette = new Uint8Array(16 * 4);
    GLOBE_PALETTE.forEach((colour, index) => {
      palette[index * 4] = Math.round(colour[0] * 255);
      palette[index * 4 + 1] = Math.round(colour[1] * 255);
      palette[index * 4 + 2] = Math.round(colour[2] * 255);
      palette[index * 4 + 3] = 255;
    });
    gl.bindTexture(gl.TEXTURE_2D, this.paletteTexture);
    gl.texImage2D(
      gl.TEXTURE_2D,
      0,
      gl.RGBA,
      16,
      1,
      0,
      gl.RGBA,
      gl.UNSIGNED_BYTE,
      palette,
    );
  }

  link(): WebGLProgram {
    const { gl } = this;
    const compile = (type: number, source: string) => {
      const shader = gl.createShader(type)!;
      gl.shaderSource(shader, source);
      gl.compileShader(shader);
      if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
        throw new Error(gl.getShaderInfoLog(shader) || 'shader did not compile');
      }
      return shader;
    };
    const program = gl.createProgram()!;
    gl.attachShader(program, compile(gl.VERTEX_SHADER, GLOBE_VERTEX_SHADER));
    gl.attachShader(program, compile(gl.FRAGMENT_SHADER, GLOBE_FRAGMENT_SHADER));
    gl.linkProgram(program);
    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
      throw new Error(gl.getProgramInfoLog(program) || 'program did not link');
    }
    return program;
  }

  makeTexture(): WebGLTexture {
    const { gl } = this;
    const texture = gl.createTexture()!;
    gl.bindTexture(gl.TEXTURE_2D, texture);
    // Exact texels: a hex's terrain must never bleed into its neighbour's by filtering.
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    return texture;
  }

  uploadCells(size: number, offset: number, data: Uint8Array) {
    const { gl } = this;
    this.cellsSize = size;
    this.cellsOffset = offset;
    gl.bindTexture(gl.TEXTURE_2D, this.cellTexture);
    gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
    gl.texImage2D(
      gl.TEXTURE_2D,
      0,
      gl.RGBA,
      size,
      size,
      0,
      gl.RGBA,
      gl.UNSIGNED_BYTE,
      data,
    );
  }

  draw(state: DrawState) {
    const { gl, locations: at } = this;
    gl.viewport(0, 0, state.width, state.height);
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, this.cellTexture);
    gl.uniform1i(at.uCells, 0);
    gl.activeTexture(gl.TEXTURE1);
    gl.bindTexture(gl.TEXTURE_2D, this.paletteTexture);
    gl.uniform1i(at.uPalette, 1);

    gl.uniform2f(at.uResolution, state.width, state.height);
    gl.uniformMatrix3fv(at.uRotation, false, new Float32Array(state.rotation));
    gl.uniform1f(at.uRadius, state.radius);
    gl.uniform1f(at.uTime, state.time);
    gl.uniform3fv(at.uSun, state.sun);
    gl.uniform3fv(at.uSunView, state.sunView);
    gl.uniform1f(at.uSeed, state.seed);
    gl.uniform3fv(at.uHome, state.frame.home);
    gl.uniform3fv(at.uEast, state.frame.east);
    gl.uniform3fv(at.uNorth, state.frame.north);
    gl.uniform1f(at.uArc, GLOBE_ARC);
    gl.uniform1f(at.uRegionRadius, state.regionRadius);
    gl.uniform1f(at.uCellsSize, this.cellsSize);
    gl.uniform1f(at.uCellsOffset, this.cellsOffset);
    gl.uniform1f(at.uTemperature, state.temperature);
    gl.uniform1f(at.uWetness, state.wetness);
    gl.uniform1f(at.uCloudOpacity, state.cloudOpacity);
    gl.uniform1f(at.uCloudShadows, state.cloudShadows);
    gl.uniform1f(at.uNightFloor, state.nightFloor);
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
  }

  /** Median milliseconds per frame over a few frames, waiting for the GPU to finish each one. */
  measure(state: DrawState, frames = 5): number {
    const { gl } = this;
    const pixel = new Uint8Array(4);
    // Untimed first: the first draws after a resize include buffer and shader setup, not drawing.
    for (let warmup = 0; warmup < 2; warmup++) {
      this.draw(state);
      gl.readPixels(0, 0, 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, pixel);
    }
    const times: number[] = [];
    for (let attempt = 0; attempt < frames; attempt++) {
      const started = performance.now();
      this.draw(state);
      gl.readPixels(0, 0, 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, pixel);
      times.push(performance.now() - started);
    }
    times.sort((a, b) => a - b);
    return times[Math.floor(times.length / 2)];
  }

  dispose() {
    const { gl } = this;
    gl.deleteTexture(this.cellTexture);
    gl.deleteTexture(this.paletteTexture);
    gl.deleteProgram(this.program);
  }
}

type DrawState = {
  width: number;
  height: number;
  rotation: Mat3;
  radius: number;
  time: number;
  sun: Vec3;
  sunView: Vec3;
  seed: number;
  frame: RegionFrame;
  regionRadius: number;
  temperature: number;
  wetness: number;
  cloudOpacity: number;
  cloudShadows: number;
  nightFloor: number;
};

type CellShape = { id: string; centre: Vec3; corners: Vec3[] };

/**
 * The region drawn on its planet.
 *
 * The WebGL canvas paints the ground; an SVG layer on top holds the hexes, so clicks, selection, the route
 * and the caravan work exactly as on the flat map. The SVG is moved by hand, not by React, on every view
 * change - re-rendering several hundred hexes per drag frame would cost more than drawing the planet.
 */
export function GlobeMap(props: Props) {
  const {
    radius,
    cells,
    knownCells,
    knownSites,
    selected,
    onSelect,
    revealAll,
    frontier,
    route,
    partyFrom,
    partyTo,
    partyProgress,
    planet,
    sun,
    quality,
    onFrameTime,
    onFailure,
  } = props;

  const containerRef = useRef<HTMLDivElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const rendererRef = useRef<GlobeRenderer | null>(null);
  const polygonRefs = useRef(new Map<string, SVGPolygonElement>());
  const markRefs = useRef(new Map<string, SVGTextElement>());
  const routeRef = useRef<SVGPolylineElement>(null);
  const partyRef = useRef<SVGCircleElement>(null);

  const seed = planet?.seed ?? 1;
  const frame = useMemo(() => regionFrame(seed), [seed]);
  const fitZoom = regionFitZoom(radius || 1);

  const viewRef = useRef({ ...viewFacing(frame.lat, frame.lon), zoom: fitZoom });
  const sizeRef = useRef({ width: 1, height: 1 });
  const dragRef = useRef<{ x: number; y: number; yaw: number; pitch: number } | null>(null);
  const movedRef = useRef(false);
  const scheduled = useRef<{ frame: number | null; timer: number | null }>({
    frame: null,
    timer: null,
  });
  const sunAnchor = useRef({ fraction: 0.4, length: 0, at: performance.now() });
  const qualityRef = useRef(quality);
  qualityRef.current = quality;

  const knownById = useMemo(() => {
    const map: Record<string, KnownCell> = {};
    for (const cell of knownCells) {
      map[cell.id] = cell;
    }
    return map;
  }, [knownCells]);

  const shapes = useMemo<CellShape[]>(
    () =>
      cells.map((cell) => {
        const [x, y] = hexFlat(cell.q, cell.r);
        const corners: Vec3[] = [];
        for (let corner = 0; corner < 6; corner++) {
          const angle = (Math.PI / 180) * (60 * corner - 90);
          corners.push(flatToSphere(frame, x + Math.cos(angle), y + Math.sin(angle)));
        }
        return { id: cell.id, centre: flatToSphere(frame, x, y), corners };
      }),
    [cells, frame],
  );

  const packed = useMemo(
    () =>
      packCellTexture(
        radius || 1,
        cells.map((cell) => ({ q: cell.q, r: cell.r, ...knownById[cell.id] })),
      ),
    [radius, cells, knownById],
  );

  if (sun) {
    const anchor = sunAnchor.current;
    if (anchor.fraction !== sun.fraction || anchor.length !== sun.day_length) {
      sunAnchor.current = { fraction: sun.fraction, length: sun.day_length, at: performance.now() };
    }
  }

  /** Builds everything the shader needs for the view as it stands now. */
  const drawState = (): DrawState => {
    const { width, height } = sizeRef.current;
    const scale = QUALITY_SCALE[qualityRef.current];
    const view = viewRef.current;
    const rotation = viewRotation(view.yaw, view.pitch);
    const anchor = sunAnchor.current;
    const fraction = anchor.length
      ? anchor.fraction + (performance.now() - anchor.at) / (anchor.length * 100)
      : anchor.fraction;
    const sunPlanet = sunDirection(frame, fraction % 1);
    // Zoomed in to plan, the night side stays readable and the clouds thin out.
    const planning = smoothstep(fitZoom * 0.45, fitZoom * 0.95, view.zoom);
    return {
      width: Math.max(1, Math.round(width * scale)),
      height: Math.max(1, Math.round(height * scale)),
      rotation,
      radius: Math.min(width, height) * view.zoom * scale,
      time: performance.now() / 1000,
      sun: sunPlanet,
      sunView: toView(rotation, sunPlanet),
      seed: (seed % 1000) / 10,
      frame,
      regionRadius: radius || 1,
      temperature: Math.max(-0.4, Math.min(0.4, ((planet?.temperature_c ?? 20) - 20) / 50)),
      wetness: Math.max(-0.3, Math.min(0.3, ((planet?.moisture ?? 50) - 50) / 150)),
      cloudOpacity: qualityRef.current === 'full' ? 0.9 - planning * 0.78 : 0,
      cloudShadows: qualityRef.current === 'full' ? 1 : 0,
      nightFloor: 0.07 + planning * 0.48,
    };
  };

  /** Moves the SVG layer to match the view. Cheap: a few thousand multiplications. */
  const updateOverlay = () => {
    const { width, height } = sizeRef.current;
    const view = viewRef.current;
    const rotation = viewRotation(view.yaw, view.pitch);
    const planetRadius = Math.min(width, height) * view.zoom;
    const hexPixels = GLOBE_ARC * planetRadius;
    const cx = width / 2;
    const cy = height / 2;
    const project = (p: Vec3): [number, number, number] => {
      const v = toView(rotation, p);
      return [cx + v[0] * planetRadius, cy - v[1] * planetRadius, v[2]];
    };

    const centres: Record<string, [number, number, number]> = {};
    for (const shape of shapes) {
      const centre = project(shape.centre);
      centres[shape.id] = centre;
      const polygon = polygonRefs.current.get(shape.id);
      if (!polygon) {
        continue;
      }
      if (centre[2] < 0.1) {
        polygon.style.display = 'none';
        continue;
      }
      polygon.style.display = '';
      let points = '';
      for (const corner of shape.corners) {
        const screen = project(corner);
        points += `${screen[0].toFixed(1)},${screen[1].toFixed(1)} `;
      }
      polygon.setAttribute('points', points);
      polygon.style.strokeOpacity = hexPixels < MIN_HEX_PIXELS && shape.id !== selected ? '0' : '';
    }

    const fontSize = Math.max(7, Math.min(22, hexPixels * 0.9));
    for (const [key, mark] of markRefs.current) {
      const cellId = mark.dataset.cell || '';
      const centre = centres[cellId];
      const small = key.startsWith('danger:') ? hexPixels < 16 : hexPixels < MIN_HEX_PIXELS;
      if (!centre || centre[2] < 0.1 || small) {
        mark.style.display = 'none';
        continue;
      }
      mark.style.display = '';
      const below = key.startsWith('danger:') ? hexPixels * 0.55 : 0;
      mark.setAttribute('x', centre[0].toFixed(1));
      mark.setAttribute('y', (centre[1] + below).toFixed(1));
      mark.setAttribute('font-size', (key.startsWith('danger:') ? fontSize * 0.7 : fontSize).toFixed(1));
    }

    const routeLine = routeRef.current;
    if (routeLine) {
      const points = (route ?? []).map((id) => centres[id]).filter(Boolean);
      const hidden = !points.length || points.some((point) => point[2] < 0.1);
      routeLine.style.display = hidden ? 'none' : '';
      routeLine.setAttribute('points', points.map((point) => `${point[0].toFixed(1)},${point[1].toFixed(1)}`).join(' '));
    }

    const marker = partyRef.current;
    if (marker) {
      const from = partyFrom ? parseCellId(partyFrom) : null;
      const to = partyTo ? parseCellId(partyTo) : null;
      if (!from) {
        marker.style.display = 'none';
      } else {
        const [fx, fy] = hexFlat(from.q, from.r);
        const [tx, ty] = to ? hexFlat(to.q, to.r) : [fx, fy];
        const progress = partyProgress ?? 0;
        const where = project(flatToSphere(frame, fx + (tx - fx) * progress, fy + (ty - fy) * progress));
        marker.style.display = where[2] < 0.1 ? 'none' : '';
        marker.setAttribute('cx', where[0].toFixed(1));
        marker.setAttribute('cy', where[1].toFixed(1));
        marker.setAttribute('r', Math.max(3, hexPixels * 0.35).toFixed(1));
      }
    }
  };

  // The latest render's view of the world. The draw loop below is made once and reads it from here.
  const live = useRef({ drawState, updateOverlay, fitZoom, onFrameTime, onFailure });
  live.current = { drawState, updateOverlay, fitZoom, onFrameTime, onFailure };

  const loop = useRef<{
    requestDraw: () => void;
    viewChanged: () => void;
    zoomBy: (factor: number) => void;
  } | null>(null);
  if (!loop.current) {
    // Draws once, then books the next frame only if something on the planet moves by itself.
    const drawNow = () => {
      scheduled.current.frame = null;
      const renderer = rendererRef.current;
      const canvas = canvasRef.current;
      if (!renderer || !canvas) {
        return;
      }
      const state = live.current.drawState();
      if (canvas.width !== state.width || canvas.height !== state.height) {
        canvas.width = state.width;
        canvas.height = state.height;
      }
      renderer.draw(state);

      if (scheduled.current.timer === null) {
        const wait = state.cloudOpacity > 0 ? CLOUD_FRAME_MS : SUN_FRAME_MS;
        scheduled.current.timer = window.setTimeout(() => {
          scheduled.current.timer = null;
          requestDraw();
        }, wait);
      }
    };
    const requestDraw = () => {
      if (document.hidden || scheduled.current.frame !== null || !rendererRef.current) {
        return;
      }
      scheduled.current.frame = requestAnimationFrame(drawNow);
    };
    const viewChanged = () => {
      live.current.updateOverlay();
      requestDraw();
    };
    const zoomBy = (factor: number) => {
      const view = viewRef.current;
      view.zoom = Math.max(MIN_ZOOM, Math.min(live.current.fitZoom * 6, view.zoom * factor));
      viewChanged();
    };
    loop.current = { requestDraw, viewChanged, zoomBy };
  }
  const { requestDraw, viewChanged, zoomBy } = loop.current;

  // WebGL, size tracking and visibility, once.
  useEffect(() => {
    const canvas = canvasRef.current;
    const container = containerRef.current;
    if (!canvas || !container) {
      return;
    }
    const gl = canvas.getContext('webgl', { antialias: false, alpha: false });
    if (!gl) {
      live.current.onFailure?.();
      return;
    }
    try {
      rendererRef.current = new GlobeRenderer(gl);
    } catch {
      live.current.onFailure?.();
      return;
    }

    const onLost = (event: Event) => {
      event.preventDefault();
      live.current.onFailure?.();
    };
    canvas.addEventListener('webglcontextlost', onLost);

    const resize = () => {
      sizeRef.current = {
        width: Math.max(1, container.clientWidth),
        height: Math.max(1, container.clientHeight),
      };
      viewChanged();
    };
    const observer = new ResizeObserver(resize);
    observer.observe(container);
    resize();

    const onVisibility = () => {
      if (!document.hidden) {
        requestDraw();
      }
    };
    document.addEventListener('visibilitychange', onVisibility);

    // Wheel listeners from React are passive, and preventDefault does nothing there.
    const onWheel = (event: WheelEvent) => {
      event.preventDefault();
      zoomBy(event.deltaY < 0 ? ZOOM_STEP : 1 / ZOOM_STEP);
    };
    container.addEventListener('wheel', onWheel, { passive: false });

    return () => {
      observer.disconnect();
      document.removeEventListener('visibilitychange', onVisibility);
      container.removeEventListener('wheel', onWheel);
      canvas.removeEventListener('webglcontextlost', onLost);
      if (scheduled.current.frame !== null) {
        cancelAnimationFrame(scheduled.current.frame);
      }
      if (scheduled.current.timer !== null) {
        clearTimeout(scheduled.current.timer);
      }
      scheduled.current = { frame: null, timer: null };
      rendererRef.current?.dispose();
      rendererRef.current = null;
    };
  }, []);

  // New terrain: upload it and draw.
  useEffect(() => {
    rendererRef.current?.uploadCells(packed.size, packed.offset, packed.data);
    requestDraw();
  }, [packed]);

  // A new planet faces the camera on its colony.
  useEffect(() => {
    viewRef.current = { ...viewFacing(frame.lat, frame.lon), zoom: fitZoom };
    viewChanged();
  }, [frame, fitZoom]);

  // Times a few frames at this quality, so the caller can step down if the machine is slow.
  useEffect(() => {
    const handle = window.setTimeout(() => {
      const renderer = rendererRef.current;
      const canvas = canvasRef.current;
      // A hidden window is throttled, and its timing would step a fast machine down for nothing.
      if (!renderer || !canvas || document.hidden) {
        return;
      }
      const state = live.current.drawState();
      canvas.width = state.width;
      canvas.height = state.height;
      live.current.onFrameTime?.(renderer.measure(state), quality);
      requestDraw();
    }, 300);
    requestDraw();
    return () => clearTimeout(handle);
  }, [quality]);

  // Every render may have added hexes or marks; place them.
  useLayoutEffect(() => {
    updateOverlay();
  });

  const onPointerDown = (event: React.PointerEvent<HTMLDivElement>) => {
    event.preventDefault();
    const view = viewRef.current;
    dragRef.current = { x: event.clientX, y: event.clientY, yaw: view.yaw, pitch: view.pitch };
    movedRef.current = false;
  };

  const onPointerMove = (event: React.PointerEvent<HTMLDivElement>) => {
    const drag = dragRef.current;
    if (!drag) {
      return;
    }
    const dx = event.clientX - drag.x;
    const dy = event.clientY - drag.y;
    if (!movedRef.current) {
      if (Math.hypot(dx, dy) < DRAG_THRESHOLD_PIXELS) {
        return;
      }
      // Captured only once it is a real drag, so a plain click still reaches the hex under it.
      movedRef.current = true;
      event.currentTarget.setPointerCapture(event.pointerId);
    }
    const { width, height } = sizeRef.current;
    const radiansPerPixel = 1 / (Math.min(width, height) * viewRef.current.zoom);
    viewRef.current.yaw = drag.yaw - dx * radiansPerPixel;
    viewRef.current.pitch = Math.max(-1.45, Math.min(1.45, drag.pitch - dy * radiansPerPixel));
    viewChanged();
  };

  const endDrag = (event: React.PointerEvent<HTMLDivElement>) => {
    dragRef.current = null;
    if (event.currentTarget.hasPointerCapture(event.pointerId)) {
      event.currentTarget.releasePointerCapture(event.pointerId);
    }
  };

  const frontierSet: Record<string, boolean> = {};
  for (const cellId of frontier ?? []) {
    frontierSet[cellId] = true;
  }
  return (
    <div
      ref={containerRef}
      style={{
        position: 'relative',
        width: '100%',
        height: '100%',
        overflow: 'hidden',
        cursor: 'grab',
        touchAction: 'none',
        userSelect: 'none',
        background: '#05070b',
      }}
      onDragStart={(event) => event.preventDefault()}
      onPointerDown={onPointerDown}
      onPointerMove={onPointerMove}
      onPointerUp={endDrag}
      onPointerCancel={endDrag}
    >
      <canvas
        ref={canvasRef}
        style={{ position: 'absolute', inset: 0, width: '100%', height: '100%' }}
      />
      <svg
        style={{ position: 'absolute', inset: 0, width: '100%', height: '100%' }}
      >
        {cells.map((cell) => {
          const known = !!knownById[cell.id] || !!revealAll;
          const isSelected = selected === cell.id;
          const isFrontier = !known && frontierSet[cell.id];
          return (
            <polygon
              key={cell.id}
              ref={(element) => {
                if (element) {
                  polygonRefs.current.set(cell.id, element);
                } else {
                  polygonRefs.current.delete(cell.id);
                }
              }}
              fill="transparent"
              stroke={isSelected ? '#ffd24a' : isFrontier ? '#9fb0c3' : known ? '#000000' : '#ffffff'}
              strokeOpacity={isSelected || isFrontier ? 1 : known ? 0.3 : 0.06}
              strokeWidth={isSelected ? 2 : isFrontier ? 1 : 0.6}
              strokeDasharray={isFrontier && !isSelected ? '4 3' : undefined}
              onClick={() => {
                // A drag that ended over a hex turned the planet; it did not pick the hex.
                if (!movedRef.current) {
                  onSelect(cell.id);
                }
              }}
            />
          );
        })}
        <Mark keyName="home" cell="0,0" text="⌂" fill="#ffffff" refs={markRefs} />
        {knownSites.map((site: KnownSite) =>
          site.cell === '0,0' ? null : (
            <Mark
              key={site.id}
              keyName={`site:${site.id}`}
              cell={site.cell}
              text={site.kind === 'resource' ? '◆' : '⌖'}
              fill={site.available ? '#ffe9a8' : '#9a927c'}
              refs={markRefs}
            />
          ),
        )}
        {knownCells
          .filter((cell) => cell.danger > 0)
          .map((cell) => (
            <Mark
              key={`danger:${cell.id}`}
              keyName={`danger:${cell.id}`}
              cell={cell.id}
              text={'!'.repeat(cell.danger)}
              fill="#ff6b6b"
              refs={markRefs}
            />
          ))}
        <polyline
          ref={routeRef}
          fill="none"
          stroke="#ffd24a"
          strokeWidth={2.5}
          strokeLinejoin="round"
          strokeLinecap="round"
          strokeDasharray="6 4"
          style={{ pointerEvents: 'none' }}
        />
        <circle
          ref={partyRef}
          fill="#c8452b"
          stroke="#f4f0e6"
          strokeWidth={2}
          style={{ pointerEvents: 'none' }}
        />
      </svg>
      <Box style={{ position: 'absolute', top: '2px', right: '2px' }}>
        <Button icon="magnifying-glass-minus" tooltip="Zoom out" onClick={() => zoomBy(1 / ZOOM_STEP)} />
        <Button icon="magnifying-glass-plus" tooltip="Zoom in" onClick={() => zoomBy(ZOOM_STEP)} />
        <Button
          icon="house"
          tooltip="Face the colony"
          onClick={() => {
            viewRef.current = { ...viewFacing(frame.lat, frame.lon), zoom: fitZoom };
            viewChanged();
          }}
        />
        <Button
          icon="earth-americas"
          tooltip="Show the whole planet"
          onClick={() => {
            viewRef.current.zoom = MIN_ZOOM + 0.04;
            viewChanged();
          }}
        />
      </Box>
    </div>
  );
}

/** A glyph pinned to a hex. Placed by updateOverlay(), never by React. */
function Mark(props: {
  keyName: string;
  cell: string;
  text: string;
  fill: string;
  refs: React.MutableRefObject<Map<string, SVGTextElement>>;
}) {
  const { keyName, cell, text, fill, refs } = props;
  return (
    <text
      ref={(element) => {
        if (element) {
          refs.current.set(keyName, element);
        } else {
          refs.current.delete(keyName);
        }
      }}
      data-cell={cell}
      fill={fill}
      textAnchor="middle"
      dominantBaseline="central"
      stroke="#000000"
      strokeWidth={0.6}
      paintOrder="stroke"
      style={{ pointerEvents: 'none', display: 'none' }}
    >
      {text}
    </text>
  );
}
