-- as-browser's web address (FiveM serves it at https://<web_baseUrl>/as-browser/...). A resource can only
-- have one HTTP handler, so sites register routes here: Browser.httpRoute('/prefix/', fn(req, res, rest)).
-- Used by Presento for imported slide backgrounds (/presento/a/<id>.svg). GET only.

local routes = {}

function Browser.httpRoute(prefix, fn)
    routes[#routes + 1] = { prefix = prefix, fn = fn }
end

SetHttpHandler(function(req, res)
    local path = (req.path or ''):gsub('%?.*$', '')
    if req.method ~= 'GET' then res.writeHead(405); return res.send('') end
    for _, r in ipairs(routes) do
        if path:sub(1, #r.prefix) == r.prefix then
            CreateThread(function()   -- routes may wait on the database
                local ok, err = pcall(r.fn, req, res, path:sub(#r.prefix + 1))
                if not ok then
                    print(('^1[as-browser] http %s failed: %s^0'):format(path, tostring(err)))
                    res.writeHead(500); res.send('')
                end
            end)
            return
        end
    end
    res.writeHead(404)
    res.send('')
end)
