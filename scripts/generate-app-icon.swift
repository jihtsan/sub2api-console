#!/usr/bin/env swift
import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
  fputs("Usage: generate-app-icon.swift <output.png>\n", stderr)
  exit(2)
}

let size = 1024
guard
  let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
  ), let context = NSGraphicsContext(bitmapImageRep: bitmap)
else {
  fputs("Unable to create bitmap context\n", stderr)
  exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high

NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: size, height: size).fill()

let shell = NSBezierPath(
  roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896),
  xRadius: 214,
  yRadius: 214
)
NSColor(calibratedRed: 0.075, green: 0.082, blue: 0.094, alpha: 1).setFill()
shell.fill()

let inset = NSBezierPath(
  roundedRect: NSRect(x: 91, y: 91, width: 842, height: 842),
  xRadius: 190,
  yRadius: 190
)
NSColor(calibratedWhite: 1, alpha: 0.10).setStroke()
inset.lineWidth = 5
inset.stroke()

let rowYs: [CGFloat] = [247, 456, 665]
let nodeColors = [
  NSColor(calibratedRed: 0.23, green: 0.82, blue: 0.54, alpha: 1),
  NSColor(calibratedRed: 0.25, green: 0.66, blue: 0.94, alpha: 1),
  NSColor(calibratedRed: 0.96, green: 0.57, blue: 0.31, alpha: 1),
]

for (index, y) in rowYs.enumerated() {
  let row = NSBezierPath(
    roundedRect: NSRect(x: 196, y: y, width: 632, height: 112),
    xRadius: 34,
    yRadius: 34
  )
  NSColor(calibratedWhite: 1, alpha: index == 1 ? 0.16 : 0.11).setFill()
  row.fill()

  nodeColors[index].setFill()
  NSBezierPath(ovalIn: NSRect(x: 242, y: y + 36, width: 40, height: 40)).fill()

  NSColor(calibratedWhite: 1, alpha: 0.34).setFill()
  NSBezierPath(
    roundedRect: NSRect(x: 315, y: y + 43, width: index == 1 ? 126 : 184, height: 26),
    xRadius: 13,
    yRadius: 13
  ).fill()
}

let pulse = NSBezierPath()
pulse.move(to: NSPoint(x: 444, y: 513))
pulse.line(to: NSPoint(x: 500, y: 513))
pulse.line(to: NSPoint(x: 540, y: 590))
pulse.line(to: NSPoint(x: 594, y: 404))
pulse.line(to: NSPoint(x: 647, y: 552))
pulse.line(to: NSPoint(x: 710, y: 552))
pulse.lineCapStyle = .round
pulse.lineJoinStyle = .round
pulse.lineWidth = 27
NSColor(calibratedWhite: 0.98, alpha: 0.96).setStroke()
pulse.stroke()

nodeColors[0].setFill()
NSBezierPath(ovalIn: NSRect(x: 745, y: 757, width: 76, height: 76)).fill()
NSColor(calibratedWhite: 1, alpha: 0.76).setFill()
NSBezierPath(ovalIn: NSRect(x: 766, y: 778, width: 20, height: 20)).fill()

context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
  fputs("Unable to encode PNG\n", stderr)
  exit(1)
}

try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
