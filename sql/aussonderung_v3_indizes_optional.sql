-- *************************************************************************************************************************
-- OPTIONAL: Indexvorschläge für die Aussonderungs-Vorbereitung (addon_prep_bewerten / _archivieren / _loeschen)
--
-- Vor dem Einspielen:
--   * prüfen, ob es bereits gleichwertige Indizes gibt (sp_helpindex 'vsg_akte' usw.)
--   * bei Produkttabellen mit dem Hersteller abstimmen
--   * Indizes kosten Schreibleistung - nur anlegen, was im Ausführungsplan tatsächlich fehlt
-- *************************************************************************************************************************

-- Hierarchie: Nachfahren eines Objekts (vater_id -> sohn_id) und die NOT EXISTS-Prüfung in addon_prep_bewerten (sohn_id -> vater_id)
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('vis_prim_hierarchie') AND name = 'ix_addon_hier_vater')
   CREATE INDEX ix_addon_hier_vater ON vis_prim_hierarchie (vater_id) INCLUDE (sohn_id);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('vis_prim_hierarchie') AND name = 'ix_addon_hier_sohn')
   CREATE INDEX ix_addon_hier_sohn ON vis_prim_hierarchie (sohn_id) INCLUDE (vater_id);
GO

-- Selektion des aussonderungsfähigen Schriftguts
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('vsg_akte') AND name = 'ix_addon_akte_aussond')
   CREATE INDEX ix_addon_akte_aussond ON vsg_akte (AUSSONDERUNGSART, ABGESCHLOSSEN, AUSSONDERUNG_AM) INCLUDE (AUSSONDSTATUS);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('vsg_vorgang') AND name = 'ix_addon_vorgang_aussond')
   CREATE INDEX ix_addon_vorgang_aussond ON vsg_vorgang (AUSSONDERUNGSART, ABGESCHLOSSEN, AUSSONDERUNG_AM) INCLUDE (AUSSONDSTATUS);
GO

-- Mappenprüfung (SAX-1019) und Mappeninhalt
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('vsg_mappeinhalt') AND name = 'ix_addon_mappeinhalt_sg')
   CREATE INDEX ix_addon_mappeinhalt_sg ON vsg_mappeinhalt (schriftgut_obj_id, primaer);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('vsg_mappeinhalt') AND name = 'ix_addon_mappeinhalt_mappe')
   CREATE INDEX ix_addon_mappeinhalt_mappe ON vsg_mappeinhalt (mappe_obj_id) INCLUDE (schriftgut_obj_id, primaer);
GO
