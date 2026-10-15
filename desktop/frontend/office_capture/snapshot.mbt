///|
fn describe(
  host : @js.Value,
  format : Format,
  rect : Rect,
) -> (Array[Region], Json, String?, String?, String?) {
  let regions : Array[Region] = []
  let geometry : Array[Json] = []
  let texts : Array[String] = []
  let mut sheet : String? = None
  let cells : Array[String] = []
  let targets = elements(
    host,
    if format == Word {
      ".word-page"
    } else {
      "section[data-sheet]"
    },
  )
  for index, node in targets {
    let b = bounds(node)
    guard rect.intersection(b) is Some(crop) else { continue }
    let normalized = crop.mapped(from=b, to={ x: 0, y: 0, width: 1, height: 1, })
    let page = if format == Word { Some(index + 1) } else { None }
    regions.push({
      index,
      page,
      x: normalized.x,
      y: normalized.y,
      width: normalized.width,
      height: normalized.height,
    })
    let target : Map[String, Json] = {
      "index": Json(index),
      "geometry": {
        "space": "rendered-page-normalized",
        "bbox": [
          Json(normalized.x),
          Json(normalized.y),
          Json(normalized.x + normalized.width),
          Json(normalized.y + normalized.height),
        ],
      },
    }
    if page is Some(page) {
      target.set("page", Json(page))
    }
    if format == Excel {
      sheet = attribute(node, "data-sheet")
      if sheet is Some(name) {
        target.set("sheet", Json(name))
      }
    }
    geometry.push(Json::object(target))
    for
      text in elements(
        node,
        if format == Word {
          "text"
        } else {
          "td[data-cell]"
        },
      ) {
      if rect.intersection(bounds(text)) is None {
        continue
      }
      let value : String = text.get_with_string("textContent")
      if !value.trim().is_empty() {
        texts.push(value)
      }
      if attribute(text, "data-cell") is Some(cell) {
        cells.push(cell)
      }
    }
  }
  let range = match (cells.get(0), cells.last()) {
    (Some(first), Some(last)) =>
      Some(if first == last { first } else { "\{first}:\{last}" })
    _ => None
  }
  let text = excerpt(texts.join("\n"))
  (
    regions,
    { "regions": Json(geometry), "cells": Json(cells) },
    if text.is_empty() {
      None
    } else {
      Some(text)
    },
    sheet,
    range,
  )
}

///|
/// Paint the original selected rectangle on its contextual crop. The saved
/// coordinates still describe the selection, not the surrounding margin.
fn decorate(
  canvas : @js.Value,
  selected : Rect,
  crop : Rect,
  scale : Double,
  label : String,
) -> Unit {
  let ctx : @js.Value = canvas.apply_with_string("getContext", ["2d"])
  let x = (selected.x - crop.x) * scale
  let y = (selected.y - crop.y) * scale
  let w = selected.width * scale
  let h = selected.height * scale
  ctx.set_with_string("strokeStyle", "#1677ff")
  ctx.set_with_string("fillStyle", "#1677ff")
  ctx.set_with_string("lineWidth", 2.0 * scale)
  ctx.apply_with_string("strokeRect", [x, y, w, h])
  let radius = 10.0 * scale
  let cx = Double::min(
    x + w,
    (canvas.get_with_string("width") : Double) - radius - scale,
  )
  let cy = Double::max(y, radius + scale)
  ctx.apply_with_string("beginPath", ([] : FixedArray[@js.Value]))
  ctx.apply_with_string("arc", [cx, cy, radius, 0.0, 6.283185307179586])
  ctx.apply_with_string("fill", ([] : FixedArray[@js.Value]))
  ctx.set_with_string("fillStyle", "white")
  ctx.set_with_string("font", "bold \{12.0 * scale}px sans-serif")
  ctx.set_with_string("textAlign", "center")
  ctx.set_with_string("textBaseline", "middle")
  ctx.apply_with_string("fillText", [
    @js.Value::cast_from(label),
    @js.Value::cast_from(cx),
    @js.Value::cast_from(cy),
  ])
}

///|
fn snapshot(
  host : @js.Value,
  format : Format,
  selected : Rect,
  visible : Rect,
  label : String,
  failure : String,
  too_large : String,
  complete : (Result[Capture, String]) -> Unit,
) -> Unit {
  let padded : Rect = {
    x: selected.x - 24,
    y: selected.y - 24,
    width: selected.width + 48,
    height: selected.height + 48,
  }
  guard padded.intersection(visible) is Some(crop) else {
    complete(Err(failure))
    return
  }
  let density : Double = @js.globalThis.get_with_string("devicePixelRatio")
  let scale = Double::min(2.0, Double::max(1.0, density))
  guard within_pixel_limit(crop, scale) else {
    complete(Err(too_large))
    return
  }
  let (regions, source, text, sheet, range) = describe(host, format, selected)
  if regions.is_empty() {
    complete(Err(failure))
    return
  }
  let options = @js.Object::new()
  let clip = @js.Object::new()
  clip.set("x", crop.x + (@js.globalThis.get_with_string("scrollX") : Double))
  clip.set("y", crop.y + (@js.globalThis.get_with_string("scrollY") : Double))
  clip.set("width", crop.width)
  clip.set("height", crop.height)
  options.set("clip", clip.to_value())
  options.set("dpr", scale)
  options.set("embedFonts", true)
  options.set("reconcile", true)
  options.set("invalidate", true)
  options.set("backgroundColor", "#ffffff")
  let fail = (_ : @js.Value) => complete(Err(failure))
  if !attempt(() => {
      let renderer : @js.Value = @js.globalThis.get_with_string("snapdom")
      let promise : @js.Value = renderer.apply_with_string("toCanvas", [
        host,
        options.to_value(),
      ])
      promise.apply_with_string("then", [
        @js.Value::cast_from((canvas : @js.Value) => {
          if !attempt(() => {
              decorate(canvas, selected, crop, scale, label)
              let url : String = canvas.apply_with_string("toDataURL", [
                "image/png",
              ])
              if png_within_limit(url) {
                complete(
                  Ok({
                    format,
                    url,
                    source,
                    regions,
                    rotation: None,
                    text,
                    sheet,
                    range,
                  }),
                )
              } else {
                complete(Err(too_large))
              }
            }) {
            complete(Err(failure))
          }
        }),
        @js.Value::cast_from(fail),
      ])
    }) {
    complete(Err(failure))
  }
}
