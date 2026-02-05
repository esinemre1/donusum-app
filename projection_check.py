
import pyproj

# ITRF96 Zone 33 (CM 33)
# proj string: +proj=tmerc +lat_0=0 +lon_0=33 +k=1 +x_0=500000 +y_0=0 +ellps=GRS80 +units=m +no_defs
proj_str = "+proj=tmerc +lat_0=0 +lon_0=33 +k=1 +x_0=500000 +y_0=0 +ellps=GRS80 +units=m +no_defs"
p = pyproj.Proj(proj_str)

# Coordinates from Beş__imardan_Mem.dns Target
# TgtY (East) = 466635.440
# TgtX (North) = 4317087.582

east = 466635.440
north = 4317087.582

lon, lat = p(east, north, inverse=True)
print(f"E: {east}, N: {north} -> Lon: {lon}, Lat: {lat}")

# Check roughly Cihanbeyli coordinates
# Cihanbeyli is approx 32.55 E, 38.65 N
