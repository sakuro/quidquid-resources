local ScanQueue = require("lib.scan_queue")

describe("ScanQueue", function()
  describe(".push", function()
    it("scans a chunk enqueued twice only once", function()
      local queue = ScanQueue.new()

      ScanQueue.enqueue(queue, 1, 3, 4)
      ScanQueue.enqueue(queue, 1, 3, 4)

      assert.are.same({ surface_index = 1, x = 3, y = 4 }, ScanQueue.dequeue(queue))
      assert.is_nil(ScanQueue.dequeue(queue))
    end)

    it("keeps the same coordinates on different surfaces distinct", function()
      local queue = ScanQueue.new()

      ScanQueue.enqueue(queue, 1, 3, 4)
      ScanQueue.enqueue(queue, 2, 3, 4)

      assert.are.same({ surface_index = 1, x = 3, y = 4 }, ScanQueue.dequeue(queue))
      assert.are.same({ surface_index = 2, x = 3, y = 4 }, ScanQueue.dequeue(queue))
      assert.is_nil(ScanQueue.dequeue(queue))
    end)

    it("allows a popped chunk to be queued again", function()
      local queue = ScanQueue.new()
      ScanQueue.enqueue(queue, 1, 3, 4)
      ScanQueue.dequeue(queue)

      ScanQueue.enqueue(queue, 1, 3, 4)

      assert.are.same({ surface_index = 1, x = 3, y = 4 }, ScanQueue.dequeue(queue))
    end)
  end)

  describe(".pop", function()
    it("returns entries in the order they were enqueued", function()
      local queue = ScanQueue.new()
      ScanQueue.enqueue(queue, 1, 0, 0)
      ScanQueue.enqueue(queue, 1, 1, 0)
      ScanQueue.enqueue(queue, 1, 2, 0)

      assert.are.equal(0, ScanQueue.dequeue(queue).x)
      assert.are.equal(1, ScanQueue.dequeue(queue).x)
      assert.are.equal(2, ScanQueue.dequeue(queue).x)
    end)

    it("returns nil once nothing remains", function()
      local queue = ScanQueue.new()

      assert.is_nil(ScanQueue.dequeue(queue))
    end)
  end)

  describe(".is_empty", function()
    it("is true only when nothing remains", function()
      local queue = ScanQueue.new()
      assert.is_true(ScanQueue.is_empty(queue))

      ScanQueue.enqueue(queue, 1, 0, 0)
      assert.is_false(ScanQueue.is_empty(queue))

      ScanQueue.dequeue(queue)
      assert.is_true(ScanQueue.is_empty(queue))
    end)
  end)

  describe("compaction", function()
    it("reclaims the consumed prefix instead of growing forever", function()
      local queue = ScanQueue.new()
      for i = 1, 100 do
        ScanQueue.enqueue(queue, 1, i, 0)
      end

      for i = 1, 90 do
        assert.are.equal(i, ScanQueue.dequeue(queue).x)
      end

      local _, array_length = ScanQueue.stats(queue)
      assert.is_true(array_length < 100)

      -- The remaining entries still pop in the order they were enqueued.
      for i = 91, 100 do
        assert.are.equal(i, ScanQueue.dequeue(queue).x)
      end
      assert.is_true(ScanQueue.is_empty(queue))
    end)

    it("never lets the backing array grow to a multiple of the outstanding count", function()
      -- Regression guard: a fixed-interval compaction policy (e.g. every N pops)
      -- would let the array grow linearly with the total ever enqueued while a
      -- large tail is still waiting, which is O(n^2) over a scan of this size.
      -- The amortised, ratio-based rule this module uses instead keeps the array
      -- within a small constant multiple of what is still outstanding.
      local queue = ScanQueue.new()
      local total = 20000
      for i = 1, total do
        ScanQueue.enqueue(queue, 1, i, 0)
      end

      local worst_ratio = 0
      for i = 1, total do
        local popped = ScanQueue.dequeue(queue)
        assert.are.equal(i, popped.x)
        local outstanding, array_length = ScanQueue.stats(queue)
        if outstanding > 0 then
          worst_ratio = math.max(worst_ratio, array_length / outstanding)
        end
      end

      assert.is_true(ScanQueue.is_empty(queue))
      -- Comfortably above the ~2x the compaction rule guarantees, but nowhere
      -- near the ~total/1 ratio an uncompacted or fixed-interval queue would hit
      -- once most of a large batch has drained.
      assert.is_true(worst_ratio <= 10)
    end)
  end)
end)
