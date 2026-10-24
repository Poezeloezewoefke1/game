package net.funcraft.games.bots;

import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.util.HashMap;
import java.util.Map;

/**
 * Small reflection helpers for reaching the server internals (Mojang names at runtime on Paper),
 * so the plugin doesn't have to be compiled against one exact server version.
 */
final class Nms {

    private static final Map<String, Method> METHODS = new HashMap<>();
    private static final Map<String, Field> FIELDS = new HashMap<>();

    private Nms() {
    }

    static Class<?> cls(String name) throws ClassNotFoundException {
        return Class.forName(name, true, Nms.class.getClassLoader());
    }

    private static Class<?> boxed(Class<?> c) {
        if (!c.isPrimitive()) {
            return c;
        }
        if (c == int.class) {
            return Integer.class;
        } else if (c == boolean.class) {
            return Boolean.class;
        } else if (c == float.class) {
            return Float.class;
        } else if (c == double.class) {
            return Double.class;
        } else if (c == long.class) {
            return Long.class;
        } else if (c == short.class) {
            return Short.class;
        } else if (c == byte.class) {
            return Byte.class;
        }
        return Character.class;
    }

    static boolean fits(Class<?>[] params, Object[] args) {
        if (params.length != args.length) {
            return false;
        }
        for (int i = 0; i < params.length; i++) {
            if (args[i] != null && !boxed(params[i]).isInstance(args[i])) {
                return false;
            }
        }
        return true;
    }

    /** Finds a method (public or not, on the class or a superclass) taking these arguments. */
    static Method method(Class<?> c, String name, Object... args) throws NoSuchMethodException {
        StringBuilder key = new StringBuilder(c.getName()).append('#').append(name);
        for (Object a : args) {
            key.append(',').append(a == null ? "null" : a.getClass().getName());
        }
        Method cached = METHODS.get(key.toString());
        if (cached != null) {
            return cached;
        }
        for (Class<?> k = c; k != null; k = k.getSuperclass()) {
            for (Method m : k.getDeclaredMethods()) {
                if (m.getName().equals(name) && fits(m.getParameterTypes(), args)) {
                    m.setAccessible(true);
                    METHODS.put(key.toString(), m);
                    return m;
                }
            }
        }
        for (Method m : c.getMethods()) {
            if (m.getName().equals(name) && fits(m.getParameterTypes(), args)) {
                m.setAccessible(true);
                METHODS.put(key.toString(), m);
                return m;
            }
        }
        throw new NoSuchMethodException(c.getName() + "." + name + " with " + args.length + " argument(s)");
    }

    static Object call(Object target, String name, Object... args) throws ReflectiveOperationException {
        return method(target.getClass(), name, args).invoke(target, args);
    }

    static Object callStatic(Class<?> c, String name, Object... args) throws ReflectiveOperationException {
        return method(c, name, args).invoke(null, args);
    }

    static Field field(Class<?> c, String name) throws NoSuchFieldException {
        String key = c.getName() + "#" + name;
        Field cached = FIELDS.get(key);
        if (cached != null) {
            return cached;
        }
        for (Class<?> k = c; k != null; k = k.getSuperclass()) {
            try {
                Field f = k.getDeclaredField(name);
                f.setAccessible(true);
                FIELDS.put(key, f);
                return f;
            } catch (NoSuchFieldException ignored) {
                // keep looking in the superclass
            }
        }
        throw new NoSuchFieldException(c.getName() + "." + name);
    }

    /** First non-static field of the given type, for when we don't know its name. */
    static Field fieldOfType(Class<?> c, Class<?> type) throws NoSuchFieldException {
        for (Class<?> k = c; k != null; k = k.getSuperclass()) {
            for (Field f : k.getDeclaredFields()) {
                if (!Modifier.isStatic(f.getModifiers()) && type.isAssignableFrom(f.getType())) {
                    f.setAccessible(true);
                    return f;
                }
            }
        }
        throw new NoSuchFieldException(c.getName() + " has no " + type.getName() + " field");
    }

    static Object get(Object target, String name) throws ReflectiveOperationException {
        return field(target.getClass(), name).get(target);
    }

    static void set(Object target, String name, Object value) throws ReflectiveOperationException {
        field(target.getClass(), name).set(target, value);
    }

    /** Builds an instance with the first constructor whose parameters can be filled from {@code values} by type. */
    static Object construct(Class<?> c, Object... values) throws ReflectiveOperationException {
        ReflectiveOperationException last = null;
        for (Constructor<?> ctor : c.getDeclaredConstructors()) {
            Class<?>[] types = ctor.getParameterTypes();
            Object[] args = new Object[types.length];
            boolean ok = true;
            for (int i = 0; i < types.length && ok; i++) {
                args[i] = pick(types[i], values);
                if (args[i] == NONE) {
                    ok = false;
                }
            }
            if (!ok) {
                continue;
            }
            try {
                ctor.setAccessible(true);
                return ctor.newInstance(args);
            } catch (ReflectiveOperationException e) {
                last = e;
            }
        }
        throw last != null ? last : new NoSuchMethodException("No usable constructor for " + c.getName());
    }

    private static final Object NONE = new Object();

    private static Object pick(Class<?> type, Object[] values) {
        for (Object v : values) {
            if (v != null && boxed(type).isInstance(v)) {
                return v;
            }
        }
        if (type == int.class) {
            return 0;
        } else if (type == boolean.class) {
            return false;
        } else if (type == long.class) {
            return 0L;
        } else if (type == float.class) {
            return 0f;
        } else if (type == double.class) {
            return 0d;
        } else if (java.util.Set.class.isAssignableFrom(type)) {
            return new java.util.HashSet<>();
        } else if (java.util.List.class.isAssignableFrom(type)) {
            return new java.util.ArrayList<>();
        } else if (java.util.Map.class.isAssignableFrom(type)) {
            return new java.util.HashMap<>();
        } else if (type == String.class || type.isPrimitive()) {
            return type.isPrimitive() ? NONE : null;
        }
        return null;
    }
}
