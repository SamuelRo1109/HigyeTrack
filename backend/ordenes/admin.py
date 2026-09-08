from django.contrib import admin

from .models import (Actividad, Arl, Ciudad, Contrato, EmpresaCliente,
                     EstadoOrden, OrdenServicio, ProfesionalHiso,
                     ResponsableArl, RpaStgOrden)


@admin.register(OrdenServicio)
class OrdenServicioAdmin(admin.ModelAdmin):
    list_display = ("numero_orden", "empresa_nombre", "actividad", "ciudad",
                    "estado", "fecha_inicio", "profesional_hiso")
    list_filter = ("estado", "arl", "ciudad")
    search_fields = ("numero_orden", "lugar_realizacion")
    date_hierarchy = "fecha_publicacion"

    @admin.display(description="Empresa")
    def empresa_nombre(self, obj):
        return obj.contrato.empresa_cliente if obj.contrato else "—"


admin.site.register([Arl, EmpresaCliente, Contrato, Ciudad, Actividad,
                     ResponsableArl, ProfesionalHiso, EstadoOrden, RpaStgOrden])