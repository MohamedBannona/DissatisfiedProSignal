--!optimize 2
--[[
This is pretty much just GoodSignal but with a doubly-linked list and a special handler for :Wait()
--]]

export type Connection<T...> = {
	Connected: boolean,
	Disconnect: (self: Connection<T...>) -> (),

	fn: (T...) -> (),
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, (T...) -> ()) -> Connection<T...>,
	Once: (self: Signal<T...>, (T...) -> ()) -> Connection<T...>,
	Fire: (self: Signal<T...>, T...) -> (),
	Wait: (self: Signal<T...>) -> T...,
	DisconnectAll: (self: Signal<T...>) -> (),

	--alias for cleanup modules
	Destroy: (self: Signal<T...>) -> (),
}

local task = task or require("@lune/task")

local spawn = task.spawn -- or task.defer

local thread = nil

local signal = {}
signal.__index = signal

local connection = {}
connection.__index = connection

local function call(fn, ...)
	local running = thread
	thread = nil
	fn(...)
	thread = running
end

local function spawner()
	while true do
		call(coroutine.yield())
	end
end

function connection:Disconnect()
	self.Connected = false

	if self.prev then
		self.prev.next = self.next
	end
	if self.next then
		self.next.prev = self.prev
	end
end

function signal.new<T...>(): Signal<T...>
	--why does setting them to false at the start slightly faster than not assigning it at start
	return setmetatable({ next = false, waiting = false }, signal) :: any
end

function signal:Connect<T...>(fn: (T...) -> ()): Connection<T...>
	local next = self.next
	local conn = setmetatable({ fn = fn, next = next, prev = self, Connected = true }, connection)

	if next then
		next.prev = conn
	end
	self.next = conn
	return conn
end

function signal:Fire<T...>(...: T...)
	local n = self.next :: Connection<T...>
	while n do
		if not thread then
			thread = coroutine.create(spawner)
			coroutine.resume(thread)
		end

		--cannot unify variadic and generic packs??
		spawn(thread, n.fn, ...)
		n = n.next
	end

	if self.waiting then
		local waiting = self.waiting
		self.waiting = false

		for i = 1, #waiting do
			spawn(waiting[i], ...)
		end
	end
end

function signal:Once<T...>(fn: (T...) -> ())
	local conn
	conn = self:Connect(function(...)
		if conn.Connected then
			conn:Disconnect()
		end
		fn(...)
	end)

	return conn
end

function signal:DisconnectAll()
	self.next = false
end
signal.Destroy = signal.DisconnectAll

function signal:Wait<T...>(): T...
	self.waiting = self.waiting or {}
	table.insert(self.waiting, coroutine.running())
	return coroutine.yield()
end

table.freeze(signal)
table.freeze(connection)
return signal
