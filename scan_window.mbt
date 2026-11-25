///|
/// Reference implementation for range-query comparisons. It decodes every grid
/// cell in logical row order and retains only selected cells.
pub fn DecodedField::scan_window(
  self : DecodedField,
  bounds : Bounds,
  max_points~ : Int32 = 1000000,
  scan_limit~ : Int32 = 10000000,
) -> Array[Sample] raise GribError {
  let (rows, columns) = window_ranges(self.grid, bounds, max_points)
  if self.grid.points > scan_limit {
    raise Unsupported(self.payload, "full-grid scan exceeds scan limit")
  }
  let result : Array[Sample] = []
  for row in 0..<self.grid.rows {
    let row_selected = row >= rows.start && row < rows.end
    let mut interval = 0
    for column in 0..<self.grid.columns {
      let sample = self.at(row, column)
      if !row_selected {
        continue
      }
      while interval < columns.length() && column >= columns[interval].end {
        interval += 1
      }
      if interval < columns.length() && column >= columns[interval].start {
        result.push(sample)
      }
    }
  }
  result
}
