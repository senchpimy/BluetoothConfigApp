# BLE Dynamic Configurator App

Esta es una aplicación de Flutter diseñada para actuar como un **configurador genérico** para dispositivos Bluetooth. En lugar de tener una interfaz de usuario fija, la aplicación se conecta a un periférico y **construye dinámicamente un formulario de configuración** basado en un esquema JSON que el propio dispositivo le proporciona.

El objetivo principal es tener una única aplicación móvil capaz de configurar diferentes tipos de dispositivos, siempre que estos sigan el protocolo BLE definido.

## Características

*   **Escaneo de Dispositivos:** Busca y muestra dispositivos BLE cuyo nombre comience con el prefijo `Configurador_`. //ps correjir
*   **Generación Dinámica de UI:** Lee una característica BLE para obtener un esquema JSON y genera un formulario con los campos correspondientes.
*   **Soporte para Múltiples Tipos de Campo:**
    *   `string`: Campo de texto estándar.
    *   `password`: Campo de texto con contenido oculto.
    *   `int`: Campo de texto que solo acepta números.
    *   `bool`: Interruptor de encendido/apagado (Switch).
*   **Envío de Configuración:** Recopila los datos del formulario, los empaqueta en un objeto JSON y los envía de vuelta al dispositivo a través de otra característica BLE.

## ⚙️ Cómo Funciona:

#### 1. Nombre del Dispositivo
La aplicación filtra los resultados del escaneo, mostrando únicamente los dispositivos cuyo nombre de publicidad (Advertising Name) comienza con el prefijo:
*   **Prefijo:** `Configurador_` (Ej: `Configurador_Termostato`, `Configurador_Luz_Jardin`).

#### 2. Servicio Principal
El dispositivo debe exponer un servicio BLE principal con el siguiente UUID:
*   **Service UUID:** `4fafc201-1fb5-459e-8fcc-c5c9c331914b`

#### 3. Características

Dentro de este servicio, debe haber dos características:

##### a) Característica de Esquema (Schema)
Esta característica le dice a la aplicación qué campos de configuración mostrar.
*   **UUID:** `beb5483e-36e1-4688-b7f5-ea07361b26a8`
*   **Propiedades:** Solo Lectura (`READ`).
*   **Valor:** Debe contener un **array JSON** en formato de string. Cada objeto en el array representa un campo del formulario.

**Ejemplo de JSON de Esquema:**
El dispositivo debe servir un string como este:
```json
[
  {
    "key": "wifi_ssid",
    "label": "Nombre de Red WiFi",
    "type": "string",
    "required": true
  },
  {
    "key": "wifi_pass",
    "label": "Contraseña WiFi",
    "type": "password"
  },
  {
    "key": "enable_feature",
    "label": "Habilitar Modo Nocturno",
    "type": "bool"
  },
  {
    "key": "device_id",
    "label": "ID del Dispositivo (1-255)",
    "type": "int"
  }
]
```
La aplicación parseará este JSON y generará el formulario correspondiente.

##### b) Característica de Datos (Data)
Esta característica es el canal por el cual la aplicación envía la configuración rellenada por el usuario.
*   **UUID:** `beb5483e-36e1-4688-b7f5-ea07361b26a9`
*   **Propiedades:** Solo Escritura (`WRITE`).
*   **Valor:** La aplicación enviará un **objeto JSON** en formato de string, donde las claves coinciden con las `key` definidas en el esquema.

**Ejemplo de JSON de Datos (enviado por la app):**
Basado en el ejemplo anterior, si un usuario rellena el formulario, la app podría enviar:
```json
{
  "wifi_ssid": "MiCasa_5G",
  "wifi_pass": "clave-secreta-123",
  "enable_feature": true,
  "device_id": 42
}
```

Se ha probado en linux y Android y solo funciona en Android.

