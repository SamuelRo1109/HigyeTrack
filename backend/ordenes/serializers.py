"""Serializadores de la API de órdenes de servicio."""

from rest_framework import serializers

from .models import (Actividad, Ciudad, EstadoOrden, OrdenHistorialEstado,
                     OrdenServicio, ProfesionalHiso)


class EstadoOrdenSerializer(serializers.ModelSerializer):
    class Meta:
        model = EstadoOrden
        fields = ["id", "codigo", "nombre", "orden_flujo", "es_inicial", "es_final"]


class CiudadSerializer(serializers.ModelSerializer):
    class Meta:
        model = Ciudad
        fields = ["id", "nombre", "genera_viaticos"]


class ActividadSerializer(serializers.ModelSerializer):
    class Meta:
        model = Actividad
        fields = ["id", "nombre"]


class ProfesionalHisoSerializer(serializers.ModelSerializer):
    class Meta:
        model = ProfesionalHiso
        fields = ["id", "documento", "nombre", "correo", "telefono", "activo"]


class OrdenHistorialEstadoSerializer(serializers.ModelSerializer):
    estado = serializers.CharField(source="estado.nombre", read_only=True)

    class Meta:
        model = OrdenHistorialEstado
        fields = ["id", "estado", "fecha_cambio", "actor", "nota"]


class OrdenServicioListSerializer(serializers.ModelSerializer):
    """Versión plana para la pantalla de listado."""

    arl = serializers.CharField(source="arl.codigo", read_only=True)
    empresa = serializers.CharField(
        source="contrato.empresa_cliente.razon_social", read_only=True, default=None
    )
    nit = serializers.CharField(
        source="contrato.empresa_cliente.nit", read_only=True, default=None
    )
    numero_contrato = serializers.CharField(
        source="contrato.numero_contrato", read_only=True, default=None
    )
    actividad = serializers.CharField(source="actividad.nombre", read_only=True)
    ciudad = serializers.CharField(source="ciudad.nombre", read_only=True)
    genera_viaticos = serializers.BooleanField(
        source="ciudad.genera_viaticos", read_only=True
    )
    estado = serializers.CharField(source="estado.nombre", read_only=True)
    estado_codigo = serializers.CharField(source="estado.codigo", read_only=True)
    profesional_hiso = serializers.CharField(
        source="profesional_hiso.nombre", read_only=True, default=None
    )
    codigo_portal = serializers.CharField(read_only=True)

    class Meta:
        model = OrdenServicio
        fields = [
            "id",
            "numero_orden",
            "codigo_portal",
            "arl",
            "nit",
            "empresa",
            "numero_contrato",
            "actividad",
            "cantidad_solicitada",
            "ciudad",
            "genera_viaticos",
            "estado",
            "estado_codigo",
            "profesional_hiso",
            "fecha_publicacion",
            "fecha_inicio",
            "fecha_fin",
            "valor_total",
        ]


class OrdenServicioDetailSerializer(OrdenServicioListSerializer):
    """Detalle de la orden, con los campos largos y el historial."""

    responsable_arl = serializers.CharField(
        source="responsable_arl.nombre", read_only=True, default=None
    )
    historial = OrdenHistorialEstadoSerializer(many=True, read_only=True)

    class Meta(OrdenServicioListSerializer.Meta):
        fields = OrdenServicioListSerializer.Meta.fields + [
            "responsable_arl",
            "lugar_realizacion",
            "contacto_actividad",
            "observaciones",
            "origen_captura",
            "fecha_captura",
            "actualizado_en",
            "historial",
        ]