"""Vistas de la API de órdenes de servicio."""

from django_filters.rest_framework import DjangoFilterBackend
from rest_framework import filters, viewsets

from .models import Ciudad, EstadoOrden, OrdenServicio, ProfesionalHiso
from .serializers import (CiudadSerializer, EstadoOrdenSerializer,
                          OrdenServicioDetailSerializer,
                          OrdenServicioListSerializer,
                          ProfesionalHisoSerializer)


class OrdenServicioViewSet(viewsets.ReadOnlyModelViewSet):
    """Consulta de órdenes de servicio.

    De momento es de solo lectura: las órdenes las crea el robot a
    través de la bandeja rpa_stg_orden, no la API.
    """

    serializer_class = OrdenServicioListSerializer
    filter_backends = [
        DjangoFilterBackend,
        filters.SearchFilter,
        filters.OrderingFilter,
    ]
    filterset_fields = {
        "arl__codigo": ["exact"],
        "estado__codigo": ["exact", "in"],
        "ciudad__nombre": ["exact"],
        "profesional_hiso": ["exact", "isnull"],
        "fecha_publicacion": ["exact", "gte", "lte"],
        "fecha_inicio": ["exact", "gte", "lte"],
    }
    search_fields = [
        "numero_orden",
        "lugar_realizacion",
        "contrato__empresa_cliente__razon_social",
        "contrato__empresa_cliente__nit",
    ]
    ordering_fields = [
        "fecha_publicacion",
        "fecha_inicio",
        "fecha_captura",
        "valor_total",
    ]
    ordering = ["-fecha_captura"]

    def get_queryset(self):
        # select_related evita una consulta por cada fila de la tabla.
        return OrdenServicio.objects.select_related(
            "arl",
            "actividad",
            "ciudad",
            "estado",
            "responsable_arl",
            "profesional_hiso",
            "contrato",
            "contrato__empresa_cliente",
        )

    def get_serializer_class(self):
        if self.action == "retrieve":
            return OrdenServicioDetailSerializer
        return OrdenServicioListSerializer


class EstadoOrdenViewSet(viewsets.ReadOnlyModelViewSet):
    """Catálogo de estados, para poblar los filtros de la interfaz."""

    queryset = EstadoOrden.objects.all()
    serializer_class = EstadoOrdenSerializer
    pagination_class = None


class CiudadViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = Ciudad.objects.all()
    serializer_class = CiudadSerializer
    pagination_class = None


class ProfesionalHisoViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = ProfesionalHiso.objects.filter(activo=True)
    serializer_class = ProfesionalHisoSerializer
    pagination_class = None