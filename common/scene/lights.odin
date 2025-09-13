package scene

import t "common:types"

Ambient_Light :: struct{
	intensity: f32
}
Point_Light :: struct {
	intensity: f32,
	position: t.Vector3
}
Directional_Light :: struct {
	intensity: f32,
	direction: t.Vector3
}
Light :: union {
	Ambient_Light,
	Point_Light,
	Directional_Light
}
