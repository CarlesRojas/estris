/**
 * The spots' motion language, after LottieFiles' motion-design skill ("Playful"): fast starts
 * with a soft landing, a little overshoot when things arrive, a squash on every click, and a
 * pointer that travels in arcs. Each helper returns CSS keyframes, all over the spot's `--d`,
 * so every animation stays one loop that ends as it starts.
 */

/** Easings. */
export const EASE = {
  /** Fast and decisive, landing softly (Material 3 standard). */
  snap: "cubic-bezier(.2, 0, 0, 1)",
  /** Ease-out-back: overshoots by about 10 % and settles, the rubber band. */
  back: "cubic-bezier(.34, 1.56, .64, 1)",
  /** Leaves quickly, for exits. */
  exit: "cubic-bezier(.3, 0, 1, 1)",
  /** Smooth both ways, for ambient loops. */
  sine: "cubic-bezier(.37, 0, .63, 1)",
};

/** A stop: [percent of the loop, x %, y %]. Two stops at the same place make a pause. */
export type Stop = [number, number, number];

/** The pointer's path. x and y each follow their own curve, so a move between two stops bends
    into an arc instead of a straight line. Use with `pointerAnimation(name)`. */
export function pointer(name: string, stops: Stop[]): string {
  const x = stops.map(([p, x]) => `${p}% { left: ${x}%; animation-timing-function: cubic-bezier(.3, 0, .1, 1); }`).join(" ");
  const y = stops.map(([p, , y]) => `${p}% { top: ${y}%; animation-timing-function: cubic-bezier(.6, 0, .25, 1); }`).join(" ");
  return `@keyframes ${name}-x { ${x} } @keyframes ${name}-y { ${y} }`;
}

export function pointerAnimation(name: string): string {
  return `${name}-x var(--d) both, ${name}-y var(--d) both`;
}

/** The pointer's button: a squash and spring back on each click, and held down while dragging
    (each drag as [from, to]). Goes on the pointer's `.press`. */
export function presses(name: string, clicks: number[], drags: [number, number][] = []): string {
  const frames: [number, string][] = [[0, "scale(1)"]];
  for (const at of clicks) {
    frames.push([at, "scale(1)"], [at + 0.6, "scale(.78)"], [at + 1.5, "scale(1.14)"], [at + 2.6, "scale(1)"]);
  }
  for (const [from, to] of drags) {
    frames.push([from, "scale(1)"], [from + 0.6, "scale(.86)"], [to, "scale(.86)"], [to + 0.9, "scale(1.1)"], [to + 2, "scale(1)"]);
  }
  frames.push([100, "scale(1)"]);
  frames.sort((a, b) => a[0] - b[0]);
  return `@keyframes ${name} { ${frames.map(([p, t]) => `${p}% { transform: ${t}; }`).join(" ")} }`;
}

/** A keycap pressed at each moment: down, then up with a little bounce, lit while down. */
export function keyPresses(name: string, at: number[], color = "var(--key-lit)"): string {
  const frames: string[] = ["0% { transform: none; background: var(--key); }"];
  for (const p of at) {
    frames.push(
      `${p}% { transform: none; background: var(--key); }`,
      `${p + 0.6}% { transform: translateY(.6cqw) scale(.94); background: ${color}; }`,
      `${p + 2}% { transform: translateY(.6cqw) scale(.94); background: ${color}; }`,
      `${p + 2.8}% { transform: translateY(-.3cqw) scale(1.04); background: var(--key); }`,
      `${p + 3.8}% { transform: none; background: var(--key); }`,
    );
  }
  frames.push("100% { transform: none; background: var(--key); }");
  return `@keyframes ${name} { ${frames.join(" ")} }`;
}

/** Something that pops in at `from` and out at `to`: up from 85 % with an overshoot, out
    quicker than it came. */
export function pop(name: string, from: number, to: number, scale = 0.85): string {
  return `@keyframes ${name} {
    0%, ${from}% { opacity: 0; transform: scale(${scale}) translateY(1.5cqw); }
    ${from}% { animation-timing-function: ${EASE.back}; }
    ${from + 4}%, ${to}% { opacity: 1; transform: none; }
    ${to}% { animation-timing-function: ${EASE.exit}; }
    ${to + 2.5}%, 100% { opacity: 0; transform: scale(.94); }
  }`;
}
