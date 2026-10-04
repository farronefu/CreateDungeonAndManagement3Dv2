class_name BlockSurfaceMesh
extends RefCounted
## One closed, stepped shell shared by every block. The vertex shader selects fixed heights.
## All geometry stays inside the existing 0.97 x 0.88 x 0.97 envelope.
const GRID := 6
const VARIANTS := 4
const DEPTH := 0.12
const HALF := Vector3(0.485, 0.44, 0.485)
const CORE := HALF - Vector3.ONE * DEPTH
const NORMALS := [Vector3.UP, Vector3.BACK, Vector3.RIGHT, Vector3.FORWARD, Vector3.LEFT, Vector3.DOWN]
const U := [Vector3.RIGHT, Vector3.RIGHT, Vector3.FORWARD, Vector3.LEFT, Vector3.BACK, Vector3.RIGHT]
const V := [Vector3.FORWARD, Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP, Vector3.BACK]

static func build() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face in 6:
		for y in GRID:
			for x in GRID:
				var cell := Vector2(x + 0.5, y + 0.5) / GRID
				_quad(st, face, Vector2(x,y)/GRID, Vector2(x+1,y)/GRID, Vector2(x,y+1)/GRID, Vector2(x+1,y+1)/GRID, cell, cell, [0.0,0.0,0.0,0.0], NORMALS[face])
		# Walls between neighboring plateaus; their winding flips with the height difference.
		for y in GRID:
			for x in range(1,GRID):
				_wall(st,face,Vector2(x,y)/GRID,Vector2(x,y+1)/GRID,Vector2(x-0.5,y+0.5)/GRID,Vector2(x+0.5,y+0.5)/GRID,U[face])
		for y in range(1,GRID):
			for x in GRID:
				_wall(st,face,Vector2(x+1,y)/GRID,Vector2(x,y)/GRID,Vector2(x+0.5,y-0.5)/GRID,Vector2(x+0.5,y+0.5)/GRID,V[face])
		# Close every raised edge down to the core; adjoining faces meet without cracks.
		for i in GRID:
			var c := (i+0.5)/GRID
			_wall(st,face,Vector2(0,i+1)/GRID,Vector2(0,i)/GRID,Vector2(0.5/GRID,c),Vector2.ONE,-U[face])
			_wall(st,face,Vector2(GRID,i)/GRID,Vector2(GRID,i+1)/GRID,Vector2(1.0-0.5/GRID,c),Vector2.ONE,U[face])
			_wall(st,face,Vector2(i,0)/GRID,Vector2(i+1,0)/GRID,Vector2(c,0.5/GRID),Vector2.ONE,-V[face])
			_wall(st,face,Vector2(i+1,GRID)/GRID,Vector2(i,GRID)/GRID,Vector2(c,1.0-0.5/GRID),Vector2.ONE,V[face])
	st.index()
	var result := st.commit()
	result.custom_aabb = AABB(-HALF,HALF*2.0)
	return result

static func _wall(st: SurfaceTool,face: int,start: Vector2,end: Vector2,a: Vector2,b: Vector2,normal: Vector3) -> void:
	_quad(st,face,start,start,end,end,a,b,[0.0,1.0,0.0,1.0],normal)

static func _quad(st: SurfaceTool,face: int,p0: Vector2,p1: Vector2,p2: Vector2,p3: Vector2,a: Vector2,b: Vector2,roles: Array,normal: Vector3) -> void:
	var points := [p0,p1,p2,p3]
	for index in [0,2,1,1,2,3]:
		var p: Vector2 = points[index]
		var n: Vector3 = NORMALS[face]
		var u: Vector3 = U[face]
		var v: Vector3 = V[face]
		var position := n * n.abs().dot(HALF) + u * ((p.x-0.5)*2.0*u.abs().dot(CORE)) + v * ((p.y-0.5)*2.0*v.abs().dot(CORE))
		# Keep each whole original atlas face, including its original moss coverage.
		var paint := p
		st.set_uv(Vector2((float(face%3)*136.0+4.0+paint.x*128.0)/408.0,(float(face/3)*136.0+4.0+(1.0-paint.y)*128.0)/272.0))
		st.set_uv2(Vector2(face,roles[index]))
		st.set_color(Color(a.x,a.y,b.x,b.y))
		st.set_normal(normal)
		st.add_vertex(position)
