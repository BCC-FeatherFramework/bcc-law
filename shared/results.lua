Law = {}
function Law.Ok(value) return { ok = true, value = value } end
function Law.Err(code, message) return { ok = false, code = code, message = message } end
function Law.Uuid(value)
    return type(value) == 'string' and value:match(
        '^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$') ~= nil
end
function Law.Text(value, maximum)
    return type(value) == 'string' and #value > 0 and #value <= maximum
        and value:find('%z') == nil and value:find('[\1-\8\11\12\14-\31\127]') == nil
end
function Law.Token(value, maximum)
    return type(value) == 'string' and #value > 0 and #value <= maximum
        and value:match('^[A-Za-z0-9][A-Za-z0-9_.:%-]*$') ~= nil
end
function Law.Fields(value, allowed)
    if type(value) ~= 'table' then return false end
    for key in pairs(value) do if not allowed[key] then return false end end
    return true
end
function Law.Copy(value)
    if type(value) ~= 'table' then return value end
    local copy = {}; for key, child in pairs(value) do copy[key] = Law.Copy(child) end
    return copy
end
