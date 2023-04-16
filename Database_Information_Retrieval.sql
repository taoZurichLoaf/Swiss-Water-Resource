-------------------------------------------------------------------------------
-- GEO875 Swiss Water Resource
-------------------------------------------------------------------------------

--Create table
CREATE TABLE project11.wms_means_data ( means_id int4 NOT NULL,
wms_id_means int4 NOT NULL,
means_date date NULL,
means_discharge float4 NULL,
means_waterlevel float4 NULL,
means_temperature float4 NULL,
CONSTRAINT wms_means_data_pk PRIMARY KEY (means_id, wms_id_means)
);
ALTER TABLE project11.wms_means_data ADD CONSTRAINT wms_means_data_fk FOREIGN KEY (wms_id_means) REFERENCES project11.water_mstaion(wms_id);

--Spatial data loading
INSERT INTO bioregion_5 (br_id,br_name,br_geom) SELECT
ROW_NUMBER() OVER (ORDER BY 1),
CASE WHEN b.br_name ILIKE '%zentralalpen%' THEN 'Zentralalpen' ELSE b.br_name END, st_force2d(st_multi(st_union(b.br_geom)))
FROM bioregion_12 b
GROUP BY
CASE WHEN b.br_name ILIKE '%zentralalpen%' THEN 'Zentralalpen' ELSE b.br_name END

--Non-spatial data loading steps
INSERT INTO wms_means_data (means_id, wms_id_means, means_date, means_discharge, means_waterlevel, means_temperature)
SELECT
ROW_NUMBER() OVER (ORDER BY 1) means_id, m.statid, m."DATE",
m."Q [m3/s]",
m."P[m a.s.l.]",
m."T [C]"
FROM project11.tmp_wms_means m ;

--Database Information Retrieval
--1. Which stations touch a river section?
SELECT w.wms_name
FROM project11.water_mstaion w
JOIN project11.river_segment r ON ST_Touches(w.wms_geom,r.rs_geom) = 'T' ;

--2. Which river sections are closer than 90 meters to a measurment station? Give the main river name (if available) and the measure station name.
SELECT rs.rs_id, rt.rt_text main_river_name, wm.wms_name, ST_Distance(rs.rs_geom, wm.wms_geom) dist
FROM project11.river_segment rs
JOIN project11.water_mstaion wm
ON ST_DWithin(rs.rs_geom, wm.wms_geom, 90) LEFT JOIN project11.riversize_type rt
ON rs.rt_code_rs = rt.rt_code ;

--3. List the shared river sections between the three cantons Zug, Zürich and Schwyz.
There is no river section going through all of these three cantons. We only find river sections going through two of those three cantons.
SELECT rs.rs_id, rs.rs_name,rs.rs_geom,count(*) AS num_canton_rs_goes_through FROM project11.river_segment rs,
(
SELECT sc.canton_geom AS geom
FROM project11.swiss_canton sc
WHERE sc.canton_name='Schwyz'OR sc.canton_name='Zürich' OR sc.canton_name='Zug' )c
WHERE st_intersects(rs.rs_geom,c.geom)='T' GROUP BY rs.rs_id
HAVING COUNT(*) > 1
ORDER BY rs.rs_id ;

--4. Which river sections connect to (=touch) the sections of main river Rhône?
SELECT DISTINCT rs2.rs_id, rs2.rs_name, rs2.rt_code_rs
FROM project11.river_segment rs
JOIN project11.river_segment rs2 ON ST_Touches(rs.rs_geom, rs2.rs_geom) LEFT JOIN project11.riversize_type rt ON rt.rt_code = rs.rt_code_rs
LEFT JOIN project11.riversize_type rt2 ON rt2.rt_code = rs2.rt_code_rs WHERE rt.rt_text = 'Rhône' AND (rt2.rt_text != 'Rhône' OR rt2.rt_text is NULL) ;

--5. What are the yearly averages and standard deviation of the pH rounded to 1 decimal at "Rhein-Weil" since ever?
SELECT EXTRACT(YEAR FROM wcd.conti_start_time) yr, round(CAST(avg(wcd.conti_ph) AS NUMERIC),1) ph_avg, round(CAST(stddev(wcd.conti_ph) AS NUMERIC),1) ph_stddev
FROM project11.wms_continuous_data wcd
GROUP BY EXTRACT(YEAR FROM wcd.conti_start_time)
ORDER BY yr ;

--6. Construct – with SQL – the main river Rhine as one single multiline geometry. How long is the river Rhine in km?
SELECT ST_length(ST_Union(rs.rs_geom))/1000 AS rhineinLength FROM project11.river_segment rs
JOIN project11.riversize_type rt ON rs.rt_code_rs=rt.rt_code WHERE rt.rt_text ILIKE 'rhein';

--7. How many river sections are completely inside one of your self-created and saved polygons and what is their length and what is the size of the respective polygon in square kilometers? Also include the name of the respective scientist and the quality rating of the polygon. Give a full list with all exemplary polygon records.
SELECT sp.poly_id, count(rs.rs_id) rs_count,
sum(st_length(rs.rs_geom))/1000 rs_length, st_area(sp.poly_geom)/1000000,
s.sci_first_name, s.sci_last_name, pa.pa_text accuracy, sp.poly_comment
FROM project11.sci_polygons sp
JOIN project11.river_segment rs ON ST_Contains(sp.poly_geom, rs.rs_geom)
JOIN project11.scientist s ON sp.sci_id_poly = s.sci_id
JOIN project11.poly_accuracy pa ON sp.poly_accuracy_code = pa.pa_code
GROUP BY sp.poly_id, st_area(sp.poly_geom), s.sci_first_name, s.sci_last_name, pa.pa_text, sp.poly_comment ;

--8. Do the daily means water temperature of the Weil am Rhein station in 2019 equal to the values from the continuous hourly measurement (aggregated per day)?
SELECT wm.wms_name,
date (wcd.conti_start_time) AS continuous_date, wmd.means_date,
AVG(wcd.conti_temperature) AS con_avg_temp_per_day, wmd.means_temperature
FROM project11.wms_continuous_data wcd
JOIN project11.water_mstaion wm ON wcd.wms_id_conti =wm.wms_id AND EXTRACT(YEAR FROM wcd.conti_start_time)=2019
JOIN project11.project11.wms_means_data wmd ON wmd.wms_id_means =wm.wms_id AND wmd.means_date=date(wcd.conti_start_time)
GROUP BY date (wcd.conti_start_time),wcd.wms_id_conti,wm.wms_name,wmd.means_date,wmd.means_tempera ture
HAVING wm.wms_name ILIKE '%weil%'
ORDER BY date (wcd.conti_start_time);

--9. Convert all cantons to geojson format in one result field. Since there are many vertices and a long output, first simplify the cantons geometries by a factor of 500. Test your multi geometry feature collection on https://geojson.io.
SELECT st_asgeojson(st_transform(ST_SimplifyPreserveTopology(sc.canton_geom, 500), 4326))
FROM project11.swiss_canton sc ;

--10.river sections that go across more than one bio region and the length of each river section in different bioregions it goes across
SELECT rs.id, rs.br_id AS predefined_br_id, b.br_name,b.br_id AS dynamic_br_id,ST_Length(ST_Intersection(b.br_geom,rs.geom)) FROM
(
SELECT s.rs_id AS id, s.rs_geom AS geom,s.br_id_5_rs AS br_id ,count(*) AS num_bio_rs_goes_through
FROM project11.river_segment s, project11.bioregion_5 b
WHERE st_intersects(s.rs_geom,b.br_geom)='T'
GROUP BY s.rs_id
HAVING COUNT(*) > 1
ORDER BY count(*) ASC
) AS rs
JOIN project11.bioregion_5 b ON ST_Intersects(b.br_geom,rs.geom)='T' ORDER BY rs.id;