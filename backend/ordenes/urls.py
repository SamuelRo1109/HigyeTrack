"""Rutas de la API de órdenes de servicio."""

from rest_framework.routers import DefaultRouter

from .views import (CiudadViewSet, EstadoOrdenViewSet, OrdenServicioViewSet,
                    ProfesionalHisoViewSet)

router = DefaultRouter()
router.register("ordenes", OrdenServicioViewSet, basename="orden")
router.register("estados", EstadoOrdenViewSet)
router.register("ciudades", CiudadViewSet)
router.register("profesionales", ProfesionalHisoViewSet)

urlpatterns = router.urls