import nimx / [ types, matrixes, animation, property_visitor ]
import rod/animation/[animation_sampler, property_animation], rod / [ quaternion, rod_types ]
import algorithm
import variant, tables, json

type
    EInterpolation* = enum
        eiLinear
        eiBezier
        eiDiscrete
        eiPresampled

    EAnimationTimeFunc* = ref object
        case kind*: EInterpolation
        of eiBezier:
            points: array[4, float]
        else:
            discard

    EditedKey* = ref object
        property*: EditedProperty
        position*: Coord
        value*: Variant
        timeFunc*: EAnimationTimeFunc

    EditedProperty* = ref object
        enabled*: bool
        rawName: string #nodeName.componentIndex.componentProperty, nodeName.nodeProperty, etc
        node: Node
        sng*: Variant
        keys*: seq[EditedKey]

    EditedAnimation* = ref object 
        fps: int
        name*: string
        duration*: float
        properties*: seq[EditedProperty]

    AbstractAnimationCurve* = ref object of RootObj
        color*: Color

    AnimationCurve*[T] = ref object of AbstractAnimationCurve
        sampler*: BezierKeyFrameAnimationSampler[T]

proc name*(e: EditedProperty): string =
    if not e.node.isNil:
        result = e.node.name
    result &= e.rawName

proc newEditedProperty*(n: Node, name: string, sng: Variant): EditedProperty =
    result.new()
    result.rawName = name
    result.sng = sng
    result.node = n
    result.enabled = true

proc sortKeys*(p: EditedProperty)=
    p.keys.sort() do(a, b: EditedKey) -> int:
        cmp(a.position, b.position)

proc addKeyAtPosition*(p: EditedProperty, pos: Coord) =
    var k = new(EditedKey)
    k.property = p
    k.position = pos
    # k.value = value

    template getKeyValue(T: typedesc) =
        let val = p.sng.get(SetterAndGetter[T]).getter()
        k.value = newVariant(val)
        # echo "value is ", val, " at pos ", pos

    template getSetterAndGetterTypeId(T: typedesc): TypeId = getTypeId(SetterAndGetter[T])
    switchAnimatableTypeId(p.sng.typeId, getSetterAndGetterTypeId, getKeyValue)
    p.keys.add(k)

    p.sortKeys()

proc keyAtIndex*(e: EditedProperty, ki: int): EditedKey =
    if ki >= 0 and ki < e.keys.len:
        return e.keys[ki]

proc propertyAtIndex*(e: EditedAnimation, pi: int): EditedProperty =
    if pi >= 0 and pi < e.properties.len:
        return e.properties[pi]

proc keyAtIndex*(e: EditedAnimation, pi, ki: int): EditedKey =
    let p = e.propertyAtIndex(pi)
    if p.isNil: return
    result = p.keyAtIndex(ki)
 
template keyValue(k: EditedKey, body: untyped) =
    template getKeyValueAUX(T: typedesc) =
        let value{.inject} = k.value.get(T)
        body
    switchAnimatableTypeId(k.value.typeId, getTypeId, getKeyValueAUX)

#todo: remove this serialization
proc `%`(q: Quaternion): JsonNode = 
    result = newJArray()
    result.add(%q.x)
    result.add(%q.y)
    result.add(%q.z)
    result.add(%q.w)

proc `%`(q: Color): JsonNode = 
    result = newJArray()
    result.add(%q.r)
    result.add(%q.g)
    result.add(%q.b)
    result.add(%q.a)

proc `%`*(a: EditedAnimation): JsonNode = 
    result = newJobject()
    # result["name"] = %a.name
    # result["duration"] = %a.duration
    for prop in a.properties:
        if not prop.enabled: continue
        var jp = newJObject()
        jp["duration"] = %a.duration #stupid?
        var keys = newJArray()
        for k in prop.keys:
            var jk = newJobject()
            jk["p"] = %k.position
            k.keyValue:
                jk["v"] = %value
            # jk["i"] = k.
            keys.add(jk)

        jp["keys"] = keys
        result[prop.name] = jp
