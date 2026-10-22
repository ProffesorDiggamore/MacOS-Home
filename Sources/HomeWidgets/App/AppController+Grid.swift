import AppKit

// Settings › General › Grid: sliding the whole grid up or down, or changing how many rows it has.
extension AppController {
    /// Re-lays every widget out in the same grid cell after the grid moves or changes rows.
    /// Widgets in rows that no longer exist move to the nearest free slot.
    func moveGrid(offset: CGFloat, rows: Int) {
        guard offset != DesktopGrid.verticalOffset || rows != DesktopGrid.rowLimit else { return }
        let before = store.widgets.map { model -> (model: WidgetModel, bounds: CGRect, cell: DesktopGrid.Cell) in
            let grid = DesktopGrid.forRect(model.frame)
            return (model, grid.bounds, grid.nearestCell(to: model.frame, size: model.size))
        }
        DesktopGrid.verticalOffset = offset
        DesktopGrid.rowLimit = rows
        var placed: [CGRect] = []
        var homeless: [WidgetModel] = []
        for item in before {
            let grid = DesktopGrid(bounds: item.bounds)
            guard grid.isFree(item.cell, size: item.model.size, occupied: placed) else {
                homeless.append(item.model)
                continue
            }
            let rect = grid.rect(at: item.cell, size: item.model.size)
            placed.append(rect)
            panels[item.model.id]?.move(to: rect, animated: false)
        }
        for model in homeless {
            let grid = DesktopGrid.forRect(model.frame)
            let rect = DesktopGrid.place(model.frame, size: model.size, occupied: placed)
                ?? grid.rect(at: grid.nearestCell(to: model.frame, size: model.size), size: model.size)
            placed.append(rect)
            panels[model.id]?.move(to: rect, animated: false)
        }
    }
}
