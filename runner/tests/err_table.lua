-- rc: 1
-- stderr-lines: 1
-- error() with something that isn't a string must not take the runner down.
function setup() error({ code = 7 }) end
