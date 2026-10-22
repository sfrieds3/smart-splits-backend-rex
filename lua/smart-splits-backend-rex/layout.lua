local M = {}

-- Return the leaf and its ancestor splits, nearest ancestor first.
function M.find(node, block)
  if type(node) ~= "table" then
    return
  end
  if node.block_id == block then
    return node, {}
  end
  if type(node.split) == "table" then
    for _, side in ipairs({ "before", "after" }) do
      local leaf, path = M.find(node.split[side], block)
      if leaf then
        path[#path + 1] = node
        return leaf, path
      end
    end
  end
end

function M.first_block(node)
  if type(node) ~= "table" then
    return
  end
  if type(node.block_id) == "string" then
    return node.block_id
  end
  if type(node.split) == "table" then
    return M.first_block(node.split.before) or M.first_block(node.split.after)
  end
end

return M
