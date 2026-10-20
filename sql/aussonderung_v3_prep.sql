-- *************************************************************************************************************************
-- Letzte Änderung:
-- Datum:         21.11.2025
-- Entwickler:    SSW
-- Bemerkung:     Hotfix Vorbereitete Aussonderung auf produktiv Umgebungen wieder zurück setzen
-- *************************************************************************************************************************
BEGIN 
   DECLARE @m_counter_jobs  INT = 0;
   DECLARE @m_jid           INT = 0;
   
   if (  dbo.IS_AUSSOND_V3_ENABLED() = 0 )
   BEGIN
       -- Aussondeurngsstatus wieder auf "in Registratur" ändern
	   update vsg_akte set version_id = -1, aussondstatus = -3031 where aussondstatus in (-10960, -10961, -10962);
	   update vsg_vorgang set version_id = -1, aussondstatus = -3031 where aussondstatus in (-10960, -10961, -10962);
	   update vsg_dokument set version_id = -1, aussondstatus = -3031 where aussondstatus in (-10960, -10961, -10962);
	   
	    CREATE TABLE #AUSSOND_JOBS
		(
		   idx INT IDENTITY PRIMARY KEY,
		   jid               INT,
        );
		
		INSERT INTO #AUSSOND_JOBS
        (
           jid
        )
        select JID from vadm_async_svc_jobs where serviceid = 53 and state != -1;
		
		WHILE @m_counter_jobs < (SELECT MAX(idx) FROM #AUSSOND_JOBS)
        BEGIN
           SET @m_counter_jobs = @m_counter_jobs + 1;
           
           SELECT @m_jid = jid FROM #AUSSOND_JOBS 
            WHERE idx = @m_counter_jobs;
            
           exec dbo.vadm_async_svc_jobs__del @m_jid;
        END; -- WHILE AUSSOND_JOBS

		DROP TABLE #AUSSOND_JOBS;
   END;
END;
GO
EXEC create_dummy 'addon_prep_bewerten', 'P '
GO
EXEC create_dummy 'addon_prep_archivieren', 'P '
GO
EXEC create_dummy 'addon_prep_dokument', 'P '
GO
EXEC create_dummy 'addon_prep_loeschen', 'P '
GO
EXEC create_dummy 'addon_aussondstatus_ex', 'P '
GO
EXEC create_dummy 'addon_aussondstatus_multi', 'P '
GO
ALTER PROCEDURE [dbo].[addon_aussondstatus_multi] (
    @i_status_id INT,
    @i_start_ltp INT = 0      -- 1 -> die Renditionbildung mit anstossen
)
AS
-- *************************************************************************************************************************
-- Letzte Änderung:
-- Datum:          20.10.2026
-- Entwickler:     Claude Code
-- Bemerkung:      Mengenbasierte Variante von addon_aussondstatus_ex.
--                 Setzt den Aussonderungsstatus rekursiv für ALLE Objekte aus #AUSSOND_ROOTS (obj_id) in einem Durchgang.
--                 #AUSSOND_ROOTS muss vom Aufrufer angelegt und befüllt werden.
--                 Akte/Vorgang/Dokument werden blockweise mengenbasiert aktualisiert statt Zeile für Zeile,
--                 vpl2_ltpprep_object wird je Dokument genau einmal aufgerufen.
-- *************************************************************************************************************************
BEGIN
    SET NOCOUNT ON

    DECLARE @m_blockgroesse INT = 4000;     -- < 5000 Sperren pro Statement -> keine Lock Escalation auf Tabellenebene
    DECLARE @m_von          INT = 1;
    DECLARE @m_max_idx      INT = 0;
    DECLARE @m_counter      INT = 0;
    DECLARE @m_obj_id       INT;

    -- Alle Nachfahren aller Startobjekte einmalig über die Hierarchie bestimmen (Mehrfachtreffer nur einmal)
    CREATE TABLE #AUSSOND_NACHFAHREN
    (
        obj_id INT NOT NULL PRIMARY KEY
    );

    INSERT INTO #AUSSOND_NACHFAHREN ( obj_id )
    SELECT DISTINCT h.sohn_id
      FROM #AUSSOND_ROOTS r
     INNER JOIN vis_prim_hierarchie h ON h.vater_id = r.obj_id
     WHERE h.sohn_id IS NOT NULL;

    CREATE TABLE #AUSSOND_ZIEL
    (
        idx          INT IDENTITY PRIMARY KEY,
        obj_id       INT NOT NULL,
        objektart_id INT NOT NULL
    );

    INSERT INTO #AUSSOND_ZIEL ( obj_id, objektart_id )
    SELECT DISTINCT sg.obj_id, sg.objektart_id
      FROM #AUSSOND_NACHFAHREN n
     INNER JOIN vsg_schriftgut_view sg ON sg.obj_id = n.obj_id
     WHERE sg.objektart_id IN (1, 3, 12, 13, 14, 15, 100, 101);

    SELECT @m_max_idx = ISNULL(MAX(idx), 0) FROM #AUSSOND_ZIEL;

    WHILE @m_von <= @m_max_idx
    BEGIN
        UPDATE a SET aussondstatus = @i_status_id, version_id = -1
          FROM vsg_akte a
         INNER JOIN #AUSSOND_ZIEL z ON z.obj_id = a.obj_id
         WHERE z.idx BETWEEN @m_von AND @m_von + @m_blockgroesse - 1
           AND z.objektart_id = 1;

        UPDATE v SET aussondstatus = @i_status_id, version_id = -1
          FROM vsg_vorgang v
         INNER JOIN #AUSSOND_ZIEL z ON z.obj_id = v.obj_id
         WHERE z.idx BETWEEN @m_von AND @m_von + @m_blockgroesse - 1
           AND z.objektart_id = 3;

        if (IsNULL(@i_start_ltp,0) <> 1)
        BEGIN
            UPDATE d SET aussondstatus = @i_status_id, version_id = -1
              FROM vsg_dokument d
             INNER JOIN #AUSSOND_ZIEL z ON z.obj_id = d.obj_id
             WHERE z.idx BETWEEN @m_von AND @m_von + @m_blockgroesse - 1
               AND z.objektart_id IN (12, 13, 14, 15, 100, 101);
        END;

        SET @m_von = @m_von + @m_blockgroesse;
    END; -- WHILE Bloecke

    if (IsNULL(@i_start_ltp,0) = 1)
    BEGIN
        -- Renditionbildung je Dokument genau einmal anstossen
        CREATE TABLE #AUSSOND_LTP
        (
            idx    INT IDENTITY PRIMARY KEY,
            obj_id INT NOT NULL
        );

        INSERT INTO #AUSSOND_LTP ( obj_id )
        SELECT DISTINCT obj_id
          FROM #AUSSOND_ZIEL
         WHERE objektart_id IN (12, 13, 14, 15, 100, 101);

        SELECT @m_max_idx = ISNULL(MAX(idx), 0) FROM #AUSSOND_LTP;

        WHILE @m_counter < @m_max_idx
        BEGIN
            SET @m_counter = @m_counter + 1;

            SELECT @m_obj_id = obj_id FROM #AUSSOND_LTP WHERE idx = @m_counter;

            exec vpl2_ltpprep_object @m_obj_id;
        END; -- WHILE AUSSOND_LTP

        DROP TABLE #AUSSOND_LTP;
    END;

    DROP TABLE #AUSSOND_ZIEL;
    DROP TABLE #AUSSOND_NACHFAHREN;
END;
    --ENDE-- addon_aussondstatus_multi --
GO
ALTER PROCEDURE [dbo].[addon_aussondstatus_ex]( @i_obj_id INT,
    @i_status_id INT,
    @i_start_ltp INT = 0      -- 1 -> die Renditionbildung mit anstossen
)
AS
-- *************************************************************************************************************************
-- Letzte Änderung:
-- Datum:          20.10.2026
-- Entwickler:     Claude Code
-- Bemerkung:      Auusonderungsstatus an Akte und Vorgang setzen 
--                 An Dokumenten immer in "Vorbereitung Langzeitspeicherung"
--                 Performance: Schnittstelle unverändert, Verarbeitung mengenbasiert über addon_aussondstatus_multi
-- *************************************************************************************************************************
BEGIN
    SET NOCOUNT ON

    if (@i_obj_id IS NULL)
    BEGIN
        return;
    END;

    CREATE TABLE #AUSSOND_ROOTS
    (
        obj_id INT NOT NULL PRIMARY KEY
    );

    INSERT INTO #AUSSOND_ROOTS ( obj_id ) VALUES ( @i_obj_id );

    exec dbo.addon_aussondstatus_multi @i_status_id, @i_start_ltp;

    DROP TABLE #AUSSOND_ROOTS;
END;
    --ENDE-- addon_aussondstatus_ex --
GO
ALTER PROCEDURE addon_prep_archivieren (
  @i_gz_mappe     NVARCHAR(150) = NULL
)
AS
-- *************************************************************************************************************************
-- Letzte Änderung:
-- Datum:         20.10.2026
-- Entwickler:    Claude Code
-- Bemerkung:     SAX-961  DB Skript um alles aussonderungsfähige Schriftgut in die Archivierenmappe zu bekommen
--                Performance: alle gefundenen Akten bzw. Vorgänge in einem Durchgang über addon_aussondstatus_multi
-- *************************************************************************************************************************
BEGIN
    SET NOCOUNT ON
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
    DECLARE @m_aussondart_archivieren INT = -3021;   -- Archivieren A
    DECLARE @m_counter_objekte     INT = 0;
    DECLARE @m_max_idx             INT = 0;
    
    DECLARE @m_obj_id              INT;
    DECLARE @m_objektart_id        INT; 
    DECLARE @m_gz                  NVARCHAR(150);
    DECLARE @m_aussondstatus       INT;
    DECLARE @m_av3_enabled         INT;
    
    DECLARE @msg                   NVARCHAR(500);
    
    EXEC set_adm_id -1;
    
    SET @m_av3_enabled = dbo.IS_AUSSOND_V3_ENABLED();
    
    IF ( IsNull(@m_av3_enabled, 0 ) = 0 )
    BEGIN
       SET @msg = 'Die Aussonderung ist auf diesem Mandanten nicht eingeschalten!';
       PRINT @msg;
       return;
    END;

    if ( LEN(ISNULL(@i_gz_mappe, '')) = 0 )
    BEGIN  
        -- Wenn keine Aussonderungsmappe übergeben wurde, alles Aussonderungsfähige Schriftgut machen
        CREATE TABLE #AUSSOND_ROOTS
        (
           obj_id INT NOT NULL PRIMARY KEY
        );
        
        INSERT INTO #AUSSOND_ROOTS ( obj_id )
        select DISTINCT OBJ_ID
        from vsg_akte
        where ABGESCHLOSSEN = 1
        and AUSSONDERUNG_AM < getdate()
        and AUSSONDERUNGSART = @m_aussondart_archivieren
        and aussondstatus not in (
           -3033,   -- in Aussonderung AV2 
           -3035,   -- 4 Augen Löschen
           -10962,  -- Langzeitspeicherung
           -10938   -- an Archiv abgegeben
        );
        
        SET @msg = CONVERT(NVARCHAR, @@ROWCOUNT) + ' Akten mit Aussonderungsart Archivieren gefunden';
        PRINT @msg;
        
        exec dbo.addon_aussondstatus_multi -10962, 0;       -- Aussonderungsstatus auf Langzeitspeicherung rekursiv setzen 
        
        -- Erst danach die Vorgänge ermitteln: Vorgänge unter den eben verarbeiteten Akten stehen jetzt auf -10962 und fallen raus
        TRUNCATE TABLE #AUSSOND_ROOTS;
        
        INSERT INTO #AUSSOND_ROOTS ( obj_id )
        select DISTINCT OBJ_ID
        from vsg_vorgang
        where ABGESCHLOSSEN = 1
        and AUSSONDERUNG_AM < getdate()
        and AUSSONDERUNGSART = @m_aussondart_archivieren
        and aussondstatus not in (
           -3033,   -- in Aussonderung AV2 
           -3035,   -- 4 Augen Löschen
           -10962,  -- Langzeitspeicherung
           -10938   -- an Archiv abgegeben
        );
        
        SET @msg = CONVERT(NVARCHAR, @@ROWCOUNT) + ' Vorgänge mit Aussonderungsart Archivieren gefunden';
        PRINT @msg;
        
        exec dbo.addon_aussondstatus_multi -10962, 1;       -- Aussonderungsstatus auf Langzeitspeicherung rekursiv setzen
        
        DROP TABLE #AUSSOND_ROOTS;
    END;
    ELSE
    BEGIN
        -- Nur alle Objekte in der mappe auf Langzeitspeicherung setzen
        
        DECLARE @mappe_obj_id  INT = null;
        DECLARE @mappe_typ_id  INT = null;
        
        select @mappe_obj_id = obj_id, @mappe_typ_id = mappetyp_id from vsg_mappe where gz = @i_gz_mappe;
        
        if ( IsNULL(@mappe_obj_id ,0 ) > 0)
        BEGIN
           CREATE TABLE #AUSSOND_SGO
           (
              idx INT IDENTITY PRIMARY KEY,
              obj_id            INT,
              objektart_id      INT,
              gz                NVARCHAR(150),
              aussondstatus     INT
           );
           
           INSERT INTO #AUSSOND_SGO
           (
              obj_id,
              objektart_id,
              gz,
              aussondstatus
           )
           select s.OBJ_ID, s.OBJEKTART_ID, s.GZ, s.AUSSONDSTATUS 
           from vsg_mappeinhalt m 
           inner join vis_prim_hierarchie h on h.vater_id = m.schriftgut_obj_id and m.primaer = 0
           inner join vsg_schriftgut_view s on h.sohn_id = s.OBJ_ID
           where m.mappe_obj_id = @mappe_obj_id;

           SET @m_max_idx = @@ROWCOUNT;
           SET @m_counter_objekte = 0;

           SET @msg = CONVERT(NVARCHAR, @m_max_idx) + ' Geschäftsobjekte in der Mappe gefunden';
           PRINT @msg;
        
           WHILE @m_counter_objekte < @m_max_idx
           BEGIN
              SET @m_counter_objekte = @m_counter_objekte + 1;
           
              SELECT @m_obj_id = obj_id,
                     @m_objektart_id = objektart_id,
                     @m_gz = gz,
                     @m_aussondstatus = aussondstatus 
              FROM #AUSSOND_SGO WHERE idx = @m_counter_objekte;
              
              if (@m_objektart_id in (1,3))
              BEGIN
                 -- Akte und Vorgang nur auf Aussonderungsstatus "Langzeitspeeicherung" setzen
                 if (@m_aussondstatus IS NULL OR @m_aussondstatus <> -10962)
                 BEGIN
                    SET @msg = 'Korrigiere Object GZ = "' + @m_gz + '" auf Aussonderungsstatus Langzeitspeicherung';
                    PRINT @msg;

                    exec dbo.vsg_aussondstatus_ex @m_obj_id, -10962, 0;         -- Aussonderungsstatus auf Langzeitspeicherung nicht rekursiv
                 END;
              END
              ELSE
              BEGIN
                 -- Dokument
                 if (@mappe_typ_id = -10943)  -- Archivierungsverzeichnis
                 BEGIN
                    exec vpl2_ltpprep_object @m_obj_id;
                 END;
              END;
            
           END; -- WHILE AUSSOND_SGOs
           
           DROP TABLE #AUSSOND_SGO;
        END
        ELSE
        BEGIN
           SET @msg = 'Das Geschäftszeichen "' + @i_gz_mappe + '" verweist nicht auf eine Mappe!';
           PRINT @msg;
        END;
    END;
END
-- END addon_prep_archivieren
GO
ALTER PROCEDURE addon_prep_bewerten (
  @i_gz_mappe     NVARCHAR(150) = NULL
)
AS
-- *************************************************************************************************************************
-- Letzte Änderung:
-- Datum:         20.10.2026
-- Entwickler:    Claude Code
-- Bemerkung:     SAX-960  DB Skript um alles aussonderungsfähige Schriftgut in die Bewertenmappe zu bekommen
--                Performance: alle gefundenen Akten bzw. Vorgänge in einem Durchgang über addon_aussondstatus_multi
-- *************************************************************************************************************************
BEGIN
    SET NOCOUNT ON
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
    DECLARE @m_aussondart_bewerten INT = -3023;   -- Bewerten
    DECLARE @m_counter_objekte     INT = 0;
    DECLARE @m_max_idx             INT = 0;
    
    DECLARE @m_obj_id              INT;
    DECLARE @m_gz                  NVARCHAR(150);
    DECLARE @m_aussondstatus       INT;
    DECLARE @m_av3_enabled         INT;
    
    DECLARE @msg                   NVARCHAR(500);
    
    EXEC set_adm_id -1;
    
    SET @m_av3_enabled = dbo.IS_AUSSOND_V3_ENABLED();
    
    IF ( IsNull(@m_av3_enabled, 0 ) = 0 )
    BEGIN
       SET @msg = 'Die Aussonderung ist auf diesem Mandanten nicht eingeschalten!';
       PRINT @msg;
       return;
    END;

    if ( LEN(ISNULL(@i_gz_mappe, '')) = 0 )
    BEGIN  
        -- Wenn keine Aussonderungsmappe übergeben wurde, alles Aussonderungsfähige Schriftgut machen
        CREATE TABLE #AUSSOND_ROOTS
        (
           obj_id INT NOT NULL PRIMARY KEY
        );
        
        INSERT INTO #AUSSOND_ROOTS ( obj_id )
        select DISTINCT OBJ_ID
        from vsg_akte
        where ABGESCHLOSSEN = 1
        and AUSSONDERUNG_AM < getdate()
        and AUSSONDERUNGSART = @m_aussondart_bewerten
        and aussondstatus not in (
           -3033,   -- in Aussonderung AV2 
           -3035,   -- 4 Augen Löschen
           -10962,  -- Langzeitspeicherung
           -10936,  -- dem Archiv angeboten
           -10937,  -- vom Archiv bewertet
           -10938   -- an Archiv abgegeben
        )
        and not exists ( SELECT mappe_obj_id FROM vsg_mappeinhalt where schriftgut_obj_id = vsg_akte.obj_id and primaer = 0);   -- SAX-1019 Objekte dürfen in keine Mappe sein
        
        SET @msg = CONVERT(NVARCHAR, @@ROWCOUNT) + ' Akten mit Aussonderungsart Bewerten gefunden';
        PRINT @msg;
        
        exec dbo.addon_aussondstatus_multi -10962, 0;       -- Aussonderungsstatus auf Langzeitspeicherung rekursiv setzen
        
        -- Erst danach die Vorgänge ermitteln: Vorgänge unter den eben verarbeiteten Akten stehen jetzt auf -10962 und fallen raus
        TRUNCATE TABLE #AUSSOND_ROOTS;
        
        INSERT INTO #AUSSOND_ROOTS ( obj_id )
        select DISTINCT OBJ_ID
        from vsg_vorgang
        where ABGESCHLOSSEN = 1
        and AUSSONDERUNG_AM < getdate()
        and AUSSONDERUNGSART = @m_aussondart_bewerten
        and aussondstatus not in (
           -3033,   -- in Aussonderung AV2 
           -3035,   -- 4 Augen Löschen
           -10962,  -- Langzeitspeicherung
           -10936,  -- dem Archiv angeboten
           -10937,  -- vom Archiv bewertet
           -10938   -- an Archiv abgegeben
        )
        and not exists ( SELECT mappe_obj_id FROM vsg_mappeinhalt inner join vis_prim_hierarchie on vsg_mappeinhalt.schriftgut_obj_id = vis_prim_hierarchie.vater_id
                          where vis_prim_hierarchie.sohn_id = vsg_vorgang.obj_id and vsg_mappeinhalt.primaer = 0 );  -- SAX-1019 Objekte dürfen in keine Mappe sein
        
        SET @msg = CONVERT(NVARCHAR, @@ROWCOUNT) + ' Vorgänge mit Aussonderungsart Bewerten gefunden';
        PRINT @msg;
        
        exec dbo.addon_aussondstatus_multi -10962, 0;       -- Aussonderungsstatus auf Langzeitspeicherung rekursiv setzen
        
        -- vor den geschachtelten Aufrufen aufräumen, die legen eigene #AUSSOND_ROOTS an
        DROP TABLE #AUSSOND_ROOTS;
        
        exec dbo.addon_prep_archivieren null;
        exec dbo.addon_prep_loeschen null;
    END;
    ELSE
    BEGIN
        -- Nur alle Objekte in der mappe auf Langzeitspeicherung setzen
        
        DECLARE @mappe_obj_id  INT = null;
        
        select @mappe_obj_id = obj_id from vsg_mappe where gz = @i_gz_mappe;
        
        if ( IsNULL(@mappe_obj_id ,0 ) > 0)
        BEGIN
           CREATE TABLE #AUSSOND_SGO
           (
              idx INT IDENTITY PRIMARY KEY,
              obj_id            INT,
              gz                NVARCHAR(150),
              aussondstatus     INT
           );
           
           INSERT INTO #AUSSOND_SGO
           (
              obj_id,
              gz,
              aussondstatus
           )
           select s.OBJ_ID, s.GZ, s.AUSSONDSTATUS 
           from vsg_mappeinhalt m 
           inner join vis_prim_hierarchie h on h.vater_id = m.schriftgut_obj_id and m.primaer = 0
           inner join vsg_schriftgut_view s on h.sohn_id = s.OBJ_ID
           where m.mappe_obj_id = @mappe_obj_id;

           SET @m_max_idx = @@ROWCOUNT;
           SET @m_counter_objekte = 0;

           SET @msg = CONVERT(NVARCHAR, @m_max_idx) + ' Geschäftsobjekte in der Mappe gefunden';
           PRINT @msg;
        
           WHILE @m_counter_objekte < @m_max_idx
           BEGIN
              SET @m_counter_objekte = @m_counter_objekte + 1;
           
              SELECT @m_obj_id = obj_id,
                     @m_gz = gz,
                     @m_aussondstatus = aussondstatus 
              FROM #AUSSOND_SGO WHERE idx = @m_counter_objekte;
              
              if ( @m_aussondstatus IS NULL OR @m_aussondstatus IN (-10961))
              BEGIN
                 SET @msg = 'Korrigiere Object GZ = "' + @m_gz + '" auf Aussonderungsstatus Langzeitspeicherung';
                 PRINT @msg;

                 exec dbo.vsg_aussondstatus_ex @m_obj_id, -10962, 0;         -- Aussonderungsstatus auf Langzeitspeicherung nicht rekursiv
              END;
            
           END; -- WHILE AUSSOND_SGOs
           
           DROP TABLE #AUSSOND_SGO;
        END
        ELSE
        BEGIN
           SET @msg = 'Das Geschäftszeichen "' + @i_gz_mappe + '" verweist nicht auf eine Mappe!';
           PRINT @msg;
        END;
    END;
END
GO
ALTER PROCEDURE [dbo].[addon_prep_dokument] (
  @i_dok_gz     NVARCHAR(150),
  @o_do_produkt INT OUTPUT 
)
AS
-- *************************************************************************************************************************
-- Letzte Änderung:
-- Datum:         13.01.2025
-- Entwickler:    SSW
-- Bemerkung:     SAX-961  Prozedure Nimmt für alle fehlerhaften Renditions das Original in das Archiv
--                @o_do_produkt = 1   führt anschließend den Produkt Code in der Regel "AussonderungV3" aus
--                @o_do_produkt = 0   führt anschließend keinen Produkt Code in der Regel "AussonderungV3" aus
-- *************************************************************************************************************************
BEGIN
    SET NOCOUNT ON
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
	SET @o_do_produkt = 0;
    
    DECLARE @m_obj_id          INT = 0;
    DECLARE @m_folder_id       INT;
    DECLARE @msg               NVARCHAR(500);
    DECLARE @m_counter_objekte INT = 0;
    DECLARE @m_vfs_id          INT;
    DECLARE @m_name            NVARCHAR(255); 
    DECLARE @m_parent_name     NVARCHAR(255); 
    DECLARE @m_parent_vfs_id   INT;
    DECLARE @m_object_type     INT;
    DECLARE @m_ltp_state       NVARCHAR(100);
    DECLARE @tmp_vfs_id        INT;
	DECLARE @m_av3_enabled         INT;
    
	
	SET @m_av3_enabled = dbo.IS_AUSSOND_V3_ENABLED();
    
    IF ( IsNull(@m_av3_enabled, 0 ) = 0 )
    BEGIN
       SET @msg = 'Die Aussonderung ist auf diesem Mandanten nicht eingeschalten!';
       PRINT @msg;
       return;
    END;
	
    SELECT @m_obj_id = obj_id FROM vsg_dokument WHERE gz = @i_dok_gz;
    
    if ( IsNULL(@m_obj_id,0) = 0 )
    BEGIN
        SELECT @msg = 'Zum übergebenen Geschäftszeichen konnte kein Dokument gefunden werden!';
        PRINT @msg;
        return;
    END;
    
    SELECT @m_folder_id = folder_id
    FROM vis_poolobjekt_tab
    WHERE obj_id = @m_obj_id;
    
    if ( IsNULL(@m_folder_id,0) > 0 )
    BEGIN
        
        CREATE TABLE #FAILED_FILES
        (
           idx INT IDENTITY PRIMARY KEY,
           vfs_id            INT,
           name              NVARCHAR(255),
           parent            INT,
           OBJECT_TYPE       INT,
           LTP_STATE         NVARCHAR(100)
        );
        
        WITH bos_vfs_objects (
                            vfs_id
                            ,NAME
                            ,PARENT
                            ,OBJECT_TYPE
                            )
                        AS (
                            SELECT fl.vfs_id
                                ,fl.NAME
                                ,fl.PARENT
                                ,fl.OBJECT_TYPE
                            FROM VFS_OBJECT_VIEW fl
                            WHERE fl.PARENT = @m_folder_id
                            UNION ALL
                            SELECT fl2.vfs_id
                                ,fl2.NAME
                                ,fl2.PARENT
                                ,fl2.OBJECT_TYPE
                            FROM VFS_OBJECT_VIEW fl2
                            JOIN bos_vfs_objects fs ON fs.vfs_id = fl2.parent
                            )
        INSERT INTO #FAILED_FILES
            (
                vfs_id,
                name,
                parent,
                OBJECT_TYPE,
                LTP_STATE
            )
        SELECT mf.vfs_id, 
               mf.name,
               mf.parent,
               mf.OBJECT_TYPE,
               fl_prop.value
        FROM bos_vfs_objects mf
        JOIN VFS_PROPERTY fl_prop ON fl_prop.VFS_ID = mf.vfs_id
            AND fl_prop.NAME = 'ltp-state'
        WHERE mf.OBJECT_TYPE IN (
                1
                ,2
                ,3
                )
            AND fl_prop.value IS NOT NULL
            AND CHARINDEX('a', fl_prop.value) > 0
            AND CHARINDEX('v', fl_prop.value) = 0
            AND CHARINDEX('o', fl_prop.value) = 0
            AND CHARINDEX('s', fl_prop.value) = 0
            AND CHARINDEX('p', fl_prop.value) = 0
            AND CHARINDEX('!', fl_prop.value) = 0;
                            
        
        SELECT @msg = CONVERT(NVARCHAR, COUNT(VFS_ID)) + ' Dateien mit ungültigen LTP-State am Dokument gefunden' FROM #FAILED_FILES;
        PRINT @msg;
        
        WHILE @m_counter_objekte < (SELECT MAX(idx) FROM #FAILED_FILES)
        BEGIN
           SET @m_counter_objekte = @m_counter_objekte + 1;
           
           SELECT @m_vfs_id        = vfs_id, 
                  @m_name          = name, 
                  @m_parent_vfs_id = parent,
                  @m_object_type   = object_type, 
                  @m_ltp_state     = ltp_state 
             FROM #FAILED_FILES
            WHERE idx = @m_counter_objekte;
            
            if (@m_object_type = 1)
            BEGIN 
               SELECT @msg = 'Korrigiere Datei ' + @m_name + ' (VFS_ID = ' + CONVERT(nvarchar,@m_vfs_id) + ') mit ungültigen LTP-State ''' + @m_ltp_state + '''';
               print @msg;
               
               if (@m_ltp_state = 'acf')
               BEGIN
                  -- Es kann keine Rendition von der Original Datei erstellt werden, also nimm die Original mit in das Archiv
                  EXEC VFSI_ADD_PROPERTY_OBJECT @m_vfs_id, 'ltp-state', 'ao'
               END;
               
               if (@m_ltp_state = 'ac')
               BEGIN
                  -- Gibt es eine Rendition zu dieser Datei mit LTP-STATE = 'av'
                  SET @tmp_vfs_id = dbo.addon_get_rendition( @m_vfs_id, 'av');
                  
                  if ( IsNULL(@tmp_vfs_id,0) > 0 )
                  BEGIN
                     -- Es gibt eine Valide Rendition 
                     EXEC VFSI_ADD_PROPERTY_OBJECT @m_vfs_id, 'ltp-state', 'p'
                  END
                  ELSE
                  BEGIN
                     -- Es gibt keine fehlerfreie Rendition -> also nimm die Original mit in das Archiv
                     EXEC VFSI_ADD_PROPERTY_OBJECT @m_vfs_id, 'ltp-state', 'ao'
                  END;
               END;
            END;
            ELSE
            if (@m_object_type = 2)
            BEGIN 
               SELECT @m_parent_name = name FROM VFS_OBJECT WHERE vfs_id = @m_parent_vfs_id;
               SELECT @msg = 'Korrigiere Dateiversion ' +  @m_parent_name + ' (VFS_ID = ' + CONVERT(nvarchar,@m_vfs_id) + ') mit ungültigen LTP-State ''' + @m_ltp_state + '''';
               print @msg;

               if (@m_ltp_state = 'acf')
               BEGIN
                  -- Es kann keine Rendition von der Dateiversion erstellt werden, also nimm die Original mit in das Archiv
                  EXEC VFSI_ADD_PROPERTY_OBJECT @m_vfs_id, 'ltp-state', 'ao'
               END;

               if (@m_ltp_state = 'ac')
               BEGIN
                  -- Gibt es eine Rendition zu dieser Dateiversion mit LTP-STATE = 'av'
                  SET @tmp_vfs_id = dbo.addon_get_rendition( @m_vfs_id, 'av');
                  
                  if ( IsNULL(@tmp_vfs_id,0) > 0 )
                  BEGIN
                     -- Es gibt eine Valide Rendition 
                     EXEC VFSI_ADD_PROPERTY_OBJECT @m_vfs_id, 'ltp-state', 'p'
                  END
                  ELSE
                  BEGIN
                     -- Es gibt keine fehlerfreie Rendition -> also nimm die Original mit in das Archiv
                    EXEC VFSI_ADD_PROPERTY_OBJECT @m_vfs_id, 'ltp-state', 'ao'
                  END;
               END;
            END;
            ELSE
            if (@m_object_type = 3)
            BEGIN 
               SELECT @m_parent_name = name FROM VFS_OBJECT WHERE vfs_id = @m_parent_vfs_id;
               SELECT @msg = 'Korrigiere Rendition ' + @m_parent_name + ' (VFS_ID = ' + CONVERT(nvarchar,@m_vfs_id) + ') mit ungültigen LTP-State ''' + @m_ltp_state + '''';
               PRINT @msg;
               
               -- Die Orignal Datei (OBJECT_TYPE = 1) der Rendition bestimmen
               DECLARE @m_vfs_id_orig INT;
               DECLARE @m_vfs_id_version INT;
               
               SET @m_vfs_id_orig = dbo.addon_get_vfsparent(@m_vfs_id, 1);
               SET @m_vfs_id_version = dbo.addon_get_vfsparent(@m_vfs_id, 2);
               
               if (IsNULL(@m_vfs_id_version,0) > 0)
               BEGIN 
                   PRINT 'Rendition zu einer Dateiversion';
                   -- die Rendition gehört zu einer Datei-Version!
                   SET @tmp_vfs_id = dbo.addon_get_rendition( @m_vfs_id_version, 'av');
                  
                   if ( IsNULL(@tmp_vfs_id,0) > 0 )
                   BEGIN
                      -- Es gibt eine Valide Rendition zur Dateiversion
                      -- An der Datei Version kann LTP STate orrigiert werden
                      EXEC VFSI_ADD_PROPERTY_OBJECT @m_vfs_id_version, 'ltp-state', 'p'
                   END
                   ELSE
                   BEGIN
                      -- Es gibt keine fehlerfreie Rendition -> also nimm die Original Dateiversion mit in das Archiv
                      EXEC VFSI_ADD_PROPERTY_OBJECT @m_vfs_id_version, 'ltp-state', 'ao'
                   END;
               END
               ELSE
               if (IsNULL(@m_vfs_id_orig,0) > 0)
               BEGIN
                  PRINT 'Rendition zu einer Datei';
                  -- die Rendition gehört zu einer Datei!
                  SET @tmp_vfs_id = dbo.addon_get_rendition( @m_vfs_id_orig, 'av');
                  
                  if ( IsNULL(@tmp_vfs_id,0) > 0 )
                  BEGIN
                      -- Es gibt eine Valide Rendition zur Datei
                      -- An der Datei Version kann LTP STate orrigiert werden
                      EXEC VFSI_ADD_PROPERTY_OBJECT @m_vfs_id_orig, 'ltp-state', 'p'
                  END
                  ELSE
                  BEGIN
                      -- Es gibt keine fehlerfreie Rendition -> also nimm die Original Dateiversion mit in das Archiv
                      EXEC VFSI_ADD_PROPERTY_OBJECT @m_vfs_id_orig, 'ltp-state', 'ao'
                  END;
               END;
               
               -- Am Ende die Fehlerhafte Revision wegschmeissen
               DELETE from VFS_PROPERTY WHERE vfs_id = @m_vfs_id AND name = 'ltp-state';
            END;
            
            
        END; -- WHILE FAILED_FILES
       
       DROP TABLE #FAILED_FILES
    END;

    UPDATE vsg_dokument SET aussondstatus = -10962 WHERE obj_id = @m_obj_id and aussondstatus = -10961;  -- Langzeitspeicher-Fehler   weg nehmen

END
-- END addon_prep_dokument
GO
ALTER PROCEDURE addon_prep_loeschen (
  @i_gz_mappe     NVARCHAR(150) = NULL
)
AS
-- *************************************************************************************************************************
-- Letzte Änderung:
-- Datum:         20.10.2026
-- Entwickler:    Claude Code
-- Bemerkung:     SAX-962  DB Skript um alles aussonderungsfähige Schriftgut mit Beertung "Löschen" in die Löschmappe  zu bekommen
--                Performance: alle gefundenen Akten bzw. Vorgänge in einem Durchgang über addon_aussondstatus_multi
-- *************************************************************************************************************************
BEGIN
    SET NOCOUNT ON
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
    DECLARE @m_aussondart_loeschen INT = -3022;   -- Vernichten
    DECLARE @m_counter_objekte     INT = 0;
    DECLARE @m_max_idx             INT = 0;
    
    DECLARE @m_obj_id              INT;
    DECLARE @m_gz                  NVARCHAR(150);
    DECLARE @m_aussondstatus       INT;
	DECLARE @m_av3_enabled         INT;
    
    DECLARE @msg                   NVARCHAR(500);
	
	SET @m_av3_enabled = dbo.IS_AUSSOND_V3_ENABLED();
    
    IF ( IsNull(@m_av3_enabled, 0 ) = 0 )
    BEGIN
       SET @msg = 'Die Aussonderung ist auf diesem Mandanten nicht eingeschalten!';
       PRINT @msg;
       return;
    END;
    
    EXEC set_adm_id -1;

    if ( LEN(ISNULL(@i_gz_mappe, '')) = 0 )
    BEGIN  
        -- Wenn keine Aussonderungsmappe übergeben wurde, alles Aussonderungsfähige Schriftgut machen
        CREATE TABLE #AUSSOND_ROOTS
        (
           obj_id INT NOT NULL PRIMARY KEY
        );
        
        INSERT INTO #AUSSOND_ROOTS ( obj_id )
        select DISTINCT OBJ_ID
        from vsg_akte
        where ABGESCHLOSSEN = 1
        and AUSSONDERUNG_AM < getdate()
        and AUSSONDERUNGSART = @m_aussondart_loeschen
        and aussondstatus not in (
           -3033,   -- in Aussonderung AV2 
           -3035,   -- 4 Augen Löschen
           -10962,  -- Langzeitspeicherung
           -10936,  -- dem Archiv angeboten
           -10937,  -- vom Archiv bewertet
           -10938   -- an Archiv abgegeben
        );
        
        SET @msg = CONVERT(NVARCHAR, @@ROWCOUNT) + ' Akten mit Aussonderungsart Vernichten gefunden';
        PRINT @msg;
        
        exec dbo.addon_aussondstatus_multi -10962, 0;       -- Aussonderungsstatus auf Langzeitspeicherung rekursiv setzen
        
        -- Erst danach die Vorgänge ermitteln: Vorgänge unter den eben verarbeiteten Akten stehen jetzt auf -10962 und fallen raus
        TRUNCATE TABLE #AUSSOND_ROOTS;
        
        INSERT INTO #AUSSOND_ROOTS ( obj_id )
        select DISTINCT OBJ_ID
        from vsg_vorgang
        where ABGESCHLOSSEN = 1
        and AUSSONDERUNG_AM < getdate()
        and AUSSONDERUNGSART = @m_aussondart_loeschen
        and aussondstatus not in (
           -3033,   -- in Aussonderung AV2 
           -3035,   -- 4 Augen Löschen
           -10962,  -- Langzeitspeicherung
           -10936,  -- dem Archiv angeboten
           -10937,  -- vom Archiv bewertet
           -10938   -- an Archiv abgegeben
        );
        
        SET @msg = CONVERT(NVARCHAR, @@ROWCOUNT) + ' Vorgänge mit Aussonderungsart Vernichten gefunden';
        PRINT @msg;
        
        exec dbo.addon_aussondstatus_multi -10962, 0;       -- Aussonderungsstatus auf Langzeitspeicherung rekursiv setzen
        
        DROP TABLE #AUSSOND_ROOTS;
    END;
    ELSE
    BEGIN
        -- Nur alle Objekte in der mappe auf Langzeitspeicherung setzen
        
        DECLARE @mappe_obj_id  INT = null;
        
        select @mappe_obj_id = obj_id from vsg_mappe where gz = @i_gz_mappe;
        
        if ( IsNULL(@mappe_obj_id ,0 ) > 0)
        BEGIN
           CREATE TABLE #AUSSOND_SGO
           (
              idx INT IDENTITY PRIMARY KEY,
              obj_id            INT,
              gz                NVARCHAR(150),
              aussondstatus     INT
           );
           
           INSERT INTO #AUSSOND_SGO
           (
              obj_id,
              gz,
              aussondstatus
           )
           select s.OBJ_ID, s.GZ, s.AUSSONDSTATUS 
           from vsg_mappeinhalt m 
           inner join vis_prim_hierarchie h on h.vater_id = m.schriftgut_obj_id and m.primaer = 0
           inner join vsg_schriftgut_view s on h.sohn_id = s.OBJ_ID
           where m.mappe_obj_id = @mappe_obj_id;

           SET @m_max_idx = @@ROWCOUNT;
           SET @m_counter_objekte = 0;

           SET @msg = CONVERT(NVARCHAR, @m_max_idx) + ' Geschäftsobjekte in der Mappe gefunden';
           PRINT @msg;
        
           WHILE @m_counter_objekte < @m_max_idx
           BEGIN
              SET @m_counter_objekte = @m_counter_objekte + 1;
           
              SELECT @m_obj_id = obj_id,
                     @m_gz = gz,
                     @m_aussondstatus = aussondstatus 
              FROM #AUSSOND_SGO WHERE idx = @m_counter_objekte;
              
              if ( @m_aussondstatus IS NULL OR @m_aussondstatus IN (-10961))
              BEGIN
                 SET @msg = 'Korrigiere Object GZ = "' + @m_gz + '" auf Aussonderungsstatus Langzeitspeicherung';
                 PRINT @msg;

                 exec dbo.vsg_aussondstatus_ex @m_obj_id, -10962, 0;         -- Aussonderungsstatus auf Langzeitspeicherung nicht rekursiv
              END;
            
           END; -- WHILE AUSSOND_SGOs
           
           DROP TABLE #AUSSOND_SGO;
        END
        ELSE
        BEGIN
           SET @msg = 'Das Geschäftszeichen "' + @i_gz_mappe + '" verweist nicht auf eine Mappe!';
           PRINT @msg;
        END;
    END;
END
-- addon_prep_loeschen
GO
