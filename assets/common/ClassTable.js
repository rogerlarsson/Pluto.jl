// EXAMPLE:

/*
cl({a: true, b: false, c: true})
 ==
"a c "
*/

export function cl(classTable) {
    if(!classTable){
        return null
    }
    return Object.entries(classTable).reduce((allClasses, [nextClass, enable]) => (enable ? nextClass + " " + allClasses : allClasses), "")
}
