local ScanQueue = {}

-- Below this many consumed entries, compaction is skipped even once consumed
-- reaches the remaining count -- see maybe_compact. Keeps a small queue from
-- shifting its handful of entries on nearly every dequeue.
local COMPACT_FLOOR = 32

--- Builds a chunk's dedup key from its surface and coordinates.
---
--- Includes the surface index, unlike lib.resource_clustering's chunk_key, so
--- chunks that share coordinates on different surfaces never collide here.
---@param surface_index number
---@param x number  chunk x, not tile x
---@param y number  chunk y, not tile y
---@return string
local function entry_key(surface_index, x, y)
  return surface_index .. ":" .. x .. "," .. y
end

--- Creates an empty queue.
---
--- The result holds only numbers, strings and nested tables -- no functions or
--- metatables -- so it round-trips through `storage` across a save/load, and a
--- spec can build and inspect one without any Factorio runtime in scope.
---@return table  { entries = {}, head = 1, pending = {} }
function ScanQueue.new()
  return { entries = {}, head = 1, pending = {} }
end

--- Reclaims the queue's consumed prefix once it has grown to at least the size
--- of the remaining tail.
---
--- Triggering on that ratio, rather than a fixed number of dequeues, keeps each
--- entry shifted O(1) times amortised: the shift this performs costs `remaining`
--- steps, and it only runs once at least `remaining` dequeues have already happened
--- since the last one, so those dequeues pay for it -- the same accounting as a
--- dynamic array's doubling growth, run in reverse as the array shrinks. A fixed
--- interval would instead re-shift a tail that is still mostly full every N dequeues,
--- which is quadratic over the hundreds of thousands of chunks an initial scan
--- of an existing save can queue. COMPACT_FLOOR stops a small queue from paying
--- for a shift on nearly every dequeue just because both sides of the ratio are tiny.
---@param queue table  from ScanQueue.new
local function maybe_compact(queue)
  local consumed = queue.head - 1
  local remaining = #queue.entries - consumed
  if consumed < COMPACT_FLOOR or consumed < remaining then
    return
  end
  for i = 1, remaining do
    queue.entries[i] = queue.entries[queue.head + i - 1]
  end
  for i = remaining + 1, #queue.entries do
    queue.entries[i] = nil
  end
  queue.head = 1
end

--- Queues a chunk for scanning, unless it is already waiting to be scanned.
---
--- A chunk already queued is a no-op, so several resource entities exhausting
--- in the same chunk on the same tick queue one rescan instead of one per
--- entity. `pending` tracks exactly the chunks currently between the queue's
--- head and its end; ScanQueue.dequeue clears a chunk's entry from it, so a chunk
--- that has already been scanned can be queued again once it changes.
---@param queue table  from ScanQueue.new
---@param surface_index number
---@param x number  chunk x, not tile x
---@param y number  chunk y, not tile y
function ScanQueue.enqueue(queue, surface_index, x, y)
  local key = entry_key(surface_index, x, y)
  if queue.pending[key] then
    return
  end
  queue.pending[key] = true
  table.insert(queue.entries, { surface_index = surface_index, x = x, y = y })
end

--- Takes the next chunk waiting to be scanned, oldest first.
---
--- Clears the chunk's dedup entry before returning, independently of whether or
--- when compaction happens to run -- see ScanQueue.enqueue.
---@param queue table  from ScanQueue.new
---@return table|nil  { surface_index, x, y } for the dequeued chunk; nil when the
--- queue is empty
function ScanQueue.dequeue(queue)
  if queue.head > #queue.entries then
    return nil
  end
  local entry = queue.entries[queue.head]
  queue.head = queue.head + 1
  queue.pending[entry_key(entry.surface_index, entry.x, entry.y)] = nil
  maybe_compact(queue)
  return entry
end

--- True when nothing is left to scan.
---@param queue table  from ScanQueue.new
---@return boolean
function ScanQueue.is_empty(queue)
  return queue.head > #queue.entries
end

--- Reports the queue's outstanding count and its backing array's current size.
---
--- Exposed for the amortised-compaction guarantee's own tests: the array size
--- is otherwise an implementation detail, but here it is exactly what
--- maybe_compact bounds relative to the outstanding count, and a spec needs to
--- observe that bound holding rather than assume it.
---@param queue table  from ScanQueue.new
---@return number  outstanding  chunks still waiting to be dequeued
---@return number  array_length  entries the backing array currently holds,
--- including any consumed prefix not yet compacted away
function ScanQueue.stats(queue)
  return #queue.entries - queue.head + 1, #queue.entries
end

return ScanQueue
