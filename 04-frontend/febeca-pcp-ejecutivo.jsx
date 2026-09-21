import React, { useState, useMemo } from "react";
import {
  ResponsiveContainer, ComposedChart, Area, Line, XAxis, YAxis, CartesianGrid,
  Tooltip, BarChart, Bar, Cell, AreaChart,
} from "recharts";
import {
  Activity, DollarSign, TrendingUp, Target, Package, ChevronDown, ArrowUpRight,
  ArrowDownRight, Circle, Boxes, Truck, Bell, AlertTriangle, Users,
} from "lucide-react";

/* Datos reales de la marca PCP exportados del SIM de Febeca.
   Venta y presupuesto en miles de dólares. */
const D = {"per":{"mes":{"0":{"art":[{"c":"22-28-012","n":"Llave para manguera liviana PVC mango naranja 1/2\" PCP","k":"Plomería","u":13.82,"q":4335,"g":3.43,"mg":0.2481,"mv":0.159},{"c":"22-13-007","n":"Canilla plástica 1/2 x 1/2\" 40 cm PCP","k":"Plomería","u":13.42,"q":19800,"g":3.47,"mg":0.2588,"mv":-0.132},{"c":"22-70-029","n":"Llave de bola liviana PVC para soldar 3/4\" PCP","k":"Plomería","u":9.88,"q":4834,"g":2.49,"mg":0.2522,"mv":1.059},{"c":"22-07-054","n":"Unión universal PVC para soldar 3/4\" PCP","k":"Plomería","u":9.85,"q":6437,"g":2.53,"mg":0.257,"mv":0.499},{"c":"22-70-019","n":"Llave de bola liviana PVC para roscar 1/2\" PCP","k":"Plomería","u":8.49,"q":7524,"g":1.97,"mg":0.2326,"mv":-0.16},{"c":"22-70-020","n":"Llave de bola liviana PVC para roscar 3/4\" PCP","k":"Plomería","u":7.35,"q":3589,"g":1.86,"mg":0.2537,"mv":-0.242},{"c":"22-07-053","n":"Unión universal PVC para soldar 1/2\" PCP","k":"Plomería","u":6.47,"q":6384,"g":1.42,"mg":0.2186,"mv":1.271},{"c":"22-07-055","n":"Unión universal PVC para soldar 1\" PCP","k":"Plomería","u":5.99,"q":2065,"g":1.61,"mg":0.2695,"mv":1.188},{"c":"22-70-028","n":"Llave de bola liviana PVC para soldar 1/2\" PCP","k":"Plomería","u":5.61,"q":5188,"g":1.12,"mg":0.1995,"mv":-0.18},{"c":"22-07-059","n":"Unión universal PVC para roscar 3/4\" PCP","k":"Plomería","u":4.34,"q":2544,"g":1.16,"mg":0.2662,"mv":0.593},{"c":"22-70-021","n":"Llave de bola liviana PVC para roscar 1\" PCP","k":"Plomería","u":3.83,"q":1150,"g":1.04,"mg":0.2724,"mv":0.013},{"c":"22-07-058","n":"Unión universal PVC para roscar 1/2\" PCP","k":"Plomería","u":3.69,"q":3072,"g":0.9,"mg":0.2447,"mv":-0.047},{"c":"22-43-063","n":"Soldadura Multiproposito 1/128 galón PCP","k":"Plomería","u":3.41,"q":2740,"g":1.1,"mg":0.324,"mv":-0.076},{"c":"22-13-008","n":"Canilla plástica 1/ 2 x 5/8\" 40 cm PCP","k":"Plomería","u":3.25,"q":5562,"g":0.45,"mg":0.1384,"mv":-0.543},{"c":"22-13-009","n":"Canilla plástica 1/2 x 1/2\" 60 cm empaque individual PCP","k":"Plomería","u":3.17,"q":2380,"g":0.95,"mg":0.3008,"mv":-0.189}],"cat":[{"c":"Plomería","v":144.54},{"c":"Material POP","v":0.99},{"c":"Exteriores","v":0.21}],"nArt":78,"tot":145.74,"totQ":87863,"totG":38.13},"1":{"art":[{"c":"22-28-012","n":"Llave para manguera liviana PVC mango naranja 1/2\" PCP","k":"Plomería","u":10.48,"q":3114,"g":3.43,"mg":0.3274,"mv":0.345},{"c":"22-13-007","n":"Canilla plástica 1/2 x 1/2\" 40 cm PCP","k":"Plomería","u":9.61,"q":13656,"g":3.47,"mg":0.3613,"mv":-0.208},{"c":"22-70-029","n":"Llave de bola liviana PVC para soldar 3/4\" PCP","k":"Plomería","u":7.6,"q":3522,"g":2.49,"mg":0.3279,"mv":1.614},{"c":"22-07-054","n":"Unión universal PVC para soldar 3/4\" PCP","k":"Plomería","u":6.8,"q":4092,"g":2.53,"mg":0.3723,"mv":0.95},{"c":"22-70-019","n":"Llave de bola liviana PVC para roscar 1/2\" PCP","k":"Plomería","u":6.21,"q":5220,"g":1.97,"mg":0.3181,"mv":-0.161},{"c":"22-70-020","n":"Llave de bola liviana PVC para roscar 3/4\" PCP","k":"Plomería","u":5.96,"q":2790,"g":1.86,"mg":0.3129,"mv":-0.245},{"c":"22-07-055","n":"Unión universal PVC para soldar 1\" PCP","k":"Plomería","u":4.36,"q":1389,"g":1.61,"mg":0.3697,"mv":2.137},{"c":"22-70-021","n":"Llave de bola liviana PVC para roscar 1\" PCP","k":"Plomería","u":3.43,"q":1006,"g":1.04,"mg":0.3039,"mv":0.1},{"c":"22-43-063","n":"Soldadura Multiproposito 1/128 galón PCP","k":"Plomería","u":3.41,"q":2740,"g":1.1,"mg":0.324,"mv":-0.076},{"c":"22-07-059","n":"Unión universal PVC para roscar 3/4\" PCP","k":"Plomería","u":3.32,"q":1836,"g":1.16,"mg":0.3486,"mv":0.81},{"c":"22-13-009","n":"Canilla plástica 1/2 x 1/2\" 60 cm empaque individual PCP","k":"Plomería","u":3.17,"q":2380,"g":0.95,"mg":0.3008,"mv":0.08},{"c":"22-07-053","n":"Unión universal PVC para soldar 1/2\" PCP","k":"Plomería","u":3.14,"q":2680,"g":1.42,"mg":0.4506,"mv":1.444},{"c":"22-70-028","n":"Llave de bola liviana PVC para soldar 1/2\" PCP","k":"Plomería","u":3.04,"q":2596,"g":1.12,"mg":0.3679,"mv":-0.332},{"c":"22-07-056","n":"Unión universal PVC para soldar 1 1/2\" PCP","k":"Plomería","u":2.94,"q":399,"g":1.0,"mg":0.3385,"mv":0.716},{"c":"22-07-058","n":"Unión universal PVC para roscar 1/2\" PCP","k":"Plomería","u":2.69,"q":2106,"g":0.9,"mg":0.3351,"mv":-0.001}],"cat":[{"c":"Plomería","v":115.82},{"c":"Material POP","v":0.99},{"c":"Exteriores","v":0.21}],"nArt":78,"tot":117.02,"totQ":61736,"totG":38.13},"rot":"Agosto 2026","meses":["8-2026"],"sup":[{"n":"CHARLY BELLO","v":36.21,"meta":25.76,"q":140.6},{"n":"LUIS LANDAETA","v":17.31,"meta":11.83,"q":146.4},{"n":"CARLOS LAGARES","v":16.07,"meta":15.51,"q":103.6},{"n":"ALEJANDRO PRIETO","v":12.39,"meta":18.83,"q":65.8},{"n":"ALEJANDRO SAAVEDRA","v":12.21,"meta":13.79,"q":88.5},{"n":"CARLOS GUANIPA","v":8.79,"meta":9.64,"q":91.1},{"n":"JESUS MUÑOZ","v":8.68,"meta":9.99,"q":86.9},{"n":"MARTIN SANTANDER","v":6.94,"meta":10.93,"q":63.5},{"n":"ELIAS JIMENEZ","v":6.83,"meta":7.17,"q":95.3},{"n":"JOSE ESTRELLA","v":6.4,"meta":6.38,"q":100.3},{"n":"DANIELA MASELLI","v":4.24,"meta":1.68,"q":252.0},{"n":"TABARDO VILLASMIL","v":3.99,"meta":3.82,"q":104.3},{"n":"NELLY PATIÑO","v":3.61,"meta":4.21,"q":85.7},{"n":"LIZMAR MARRERO","v":2.02,"meta":2.2,"q":91.8},{"n":"LUISA CABRERA","v":0.01,"meta":0.01,"q":null}],"est":[{"n":"Carabobo","v":39.18},{"n":"Anzoátegui","v":15.15},{"n":"Zulia","v":14.14},{"n":"Distrito Capital","v":11.99},{"n":"Bolívar","v":9.64},{"n":"Aragua","v":8.44},{"n":"Lara","v":7.26},{"n":"Miranda","v":6.57},{"n":"Nueva Esparta","v":3.99},{"n":"Sucre","v":3.95},{"n":"Mérida","v":3.94},{"n":"Falcón","v":3.14}],"reg":[{"n":"CENTRO","v":56.57},{"n":"Oriente","v":35.88},{"n":"Occidente","v":32.63},{"n":"Capital","v":20.61}],"cli0":[{"n":"FERRETERIA EPA, C.A.","v":28.72},{"n":"FERRE KSA JH, C.A.","v":5.09},{"n":"FERROCERAMICA VALCRO,C.A.","v":4.64},{"n":"FERREMETALES LICCIONI, C.A","v":2.94},{"n":"GRUPO ISO HOME, C.A","v":2.86},{"n":"GRUPO EMPRESARIAL VENTE, C.A","v":2.85},{"n":"MAQUINARIAS LA PROSPERIDAD 1, C.A","v":1.44},{"n":"FERREINVICTA, C.A.","v":1.38},{"n":"DECORE MARGARITA C.A.","v":1.37},{"n":"FERRETERIA MATERIALES PUERTO FEMAPUERTO, C.A","v":1.29},{"n":"FAZ FERREAUTO ZULIA, C.A.","v":1.24},{"n":"GERARDO JOSE MARQUEZ ESCALANTE","v":1.21},{"n":"INVERSIONES DOBLE H.G, C.A","v":1.17},{"n":"MULTIGLOBAL VENEZUELA, C.A.","v":1.17},{"n":"FERRETERIA ARCI C.A.","v":1.07}],"cli1":[{"n":"FERRE KSA JH, C.A.","v":5.09},{"n":"FERROCERAMICA VALCRO,C.A.","v":4.64},{"n":"FERREMETALES LICCIONI, C.A","v":2.94},{"n":"GRUPO ISO HOME, C.A","v":2.86},{"n":"GRUPO EMPRESARIAL VENTE, C.A","v":2.85},{"n":"MAQUINARIAS LA PROSPERIDAD 1, C.A","v":1.44},{"n":"FERREINVICTA, C.A.","v":1.38},{"n":"DECORE MARGARITA C.A.","v":1.37},{"n":"FERRETERIA MATERIALES PUERTO FEMAPUERTO, C.A","v":1.29},{"n":"FAZ FERREAUTO ZULIA, C.A.","v":1.24},{"n":"GERARDO JOSE MARQUEZ ESCALANTE","v":1.21},{"n":"INVERSIONES DOBLE H.G, C.A","v":1.17},{"n":"MULTIGLOBAL VENEZUELA, C.A.","v":1.17},{"n":"FERRETERIA ARCI C.A.","v":1.07},{"n":"MUNDO HOGAR 2020, C.A","v":1.06}],"presup":141.75},"trimestre":{"0":{"art":[{"c":"22-13-007","n":"Canilla plástica 1/2 x 1/2\" 40 cm PCP","k":"Plomería","u":43.08,"q":62929,"g":11.47,"mg":0.2663,"mv":0.261},{"c":"22-28-012","n":"Llave para manguera liviana PVC mango naranja 1/2\" PCP","k":"Plomería","u":40.27,"q":13146,"g":9.15,"mg":0.2271,"mv":0.118},{"c":"22-70-019","n":"Llave de bola liviana PVC para roscar 1/2\" PCP","k":"Plomería","u":27.93,"q":24863,"g":6.83,"mg":0.2447,"mv":0.14},{"c":"22-07-054","n":"Unión universal PVC para soldar 3/4\" PCP","k":"Plomería","u":25.25,"q":17465,"g":5.6,"mg":0.2218,"mv":0.088},{"c":"22-70-020","n":"Llave de bola liviana PVC para roscar 3/4\" PCP","k":"Plomería","u":24.88,"q":12328,"g":6.17,"mg":0.2479,"mv":0.224},{"c":"22-70-028","n":"Llave de bola liviana PVC para soldar 1/2\" PCP","k":"Plomería","u":19.76,"q":18052,"g":4.59,"mg":0.2322,"mv":0.285},{"c":"22-70-029","n":"Llave de bola liviana PVC para soldar 3/4\" PCP","k":"Plomería","u":19.44,"q":9897,"g":4.43,"mg":0.2277,"mv":0.138},{"c":"22-07-053","n":"Unión universal PVC para soldar 1/2\" PCP","k":"Plomería","u":18.18,"q":18488,"g":3.94,"mg":0.2169,"mv":0.2},{"c":"22-13-008","n":"Canilla plástica 1/ 2 x 5/8\" 40 cm PCP","k":"Plomería","u":16.9,"q":25650,"g":3.89,"mg":0.23,"mv":-0.046},{"c":"22-07-055","n":"Unión universal PVC para soldar 1\" PCP","k":"Plomería","u":13.91,"q":5136,"g":3.22,"mg":0.2317,"mv":0.099},{"c":"22-07-058","n":"Unión universal PVC para roscar 1/2\" PCP","k":"Plomería","u":11.21,"q":9706,"g":2.54,"mg":0.227,"mv":0.123},{"c":"22-13-009","n":"Canilla plástica 1/2 x 1/2\" 60 cm empaque individual PCP","k":"Plomería","u":11.02,"q":8346,"g":3.24,"mg":0.2943,"mv":0.923},{"c":"22-70-021","n":"Llave de bola liviana PVC para roscar 1\" PCP","k":"Plomería","u":10.76,"q":3234,"g":2.98,"mg":0.2767,"mv":0.279},{"c":"22-07-059","n":"Unión universal PVC para roscar 3/4\" PCP","k":"Plomería","u":9.42,"q":5876,"g":2.1,"mg":0.2229,"mv":-0.206},{"c":"22-43-063","n":"Soldadura Multiproposito 1/128 galón PCP","k":"Plomería","u":8.7,"q":6692,"g":3.07,"mg":0.3532,"mv":0.953}],"cat":[{"c":"Plomería","v":433.03},{"c":"Material POP","v":1.82},{"c":"Exteriores","v":0.63}],"nArt":81,"tot":435.48,"totQ":277439,"totG":112.02},"1":{"art":[{"c":"22-13-007","n":"Canilla plástica 1/2 x 1/2\" 40 cm PCP","k":"Plomería","u":30.94,"q":43346,"g":11.47,"mg":0.3708,"mv":-0.095},{"c":"22-28-012","n":"Llave para manguera liviana PVC mango naranja 1/2\" PCP","k":"Plomería","u":26.47,"q":8109,"g":9.15,"mg":0.3456,"mv":-0.236},{"c":"22-70-020","n":"Llave de bola liviana PVC para roscar 3/4\" PCP","k":"Plomería","u":19.04,"q":8969,"g":6.17,"mg":0.3239,"mv":-0.064},{"c":"22-70-019","n":"Llave de bola liviana PVC para roscar 1/2\" PCP","k":"Plomería","u":18.09,"q":14928,"g":6.83,"mg":0.3778,"mv":-0.253},{"c":"22-07-054","n":"Unión universal PVC para soldar 3/4\" PCP","k":"Plomería","u":14.66,"q":9319,"g":5.6,"mg":0.3821,"mv":-0.309},{"c":"22-70-029","n":"Llave de bola liviana PVC para soldar 3/4\" PCP","k":"Plomería","u":13.44,"q":6446,"g":4.43,"mg":0.3294,"mv":-0.2},{"c":"22-70-028","n":"Llave de bola liviana PVC para soldar 1/2\" PCP","k":"Plomería","u":11.35,"q":9556,"g":4.59,"mg":0.4042,"mv":-0.248},{"c":"22-13-008","n":"Canilla plástica 1/ 2 x 5/8\" 40 cm PCP","k":"Plomería","u":10.53,"q":15378,"g":3.89,"mg":0.3692,"mv":-0.404},{"c":"22-70-021","n":"Llave de bola liviana PVC para roscar 1\" PCP","k":"Plomería","u":8.91,"q":2562,"g":2.98,"mg":0.3341,"mv":0.111},{"c":"22-13-009","n":"Canilla plástica 1/2 x 1/2\" 60 cm empaque individual PCP","k":"Plomería","u":8.83,"q":6408,"g":3.24,"mg":0.3673,"mv":0.571},{"c":"22-07-053","n":"Unión universal PVC para soldar 1/2\" PCP","k":"Plomería","u":8.71,"q":7972,"g":3.94,"mg":0.4525,"mv":-0.319},{"c":"22-43-063","n":"Soldadura Multiproposito 1/128 galón PCP","k":"Plomería","u":8.7,"q":6692,"g":3.07,"mg":0.3532,"mv":0.953},{"c":"22-07-055","n":"Unión universal PVC para soldar 1\" PCP","k":"Plomería","u":8.39,"q":2837,"g":3.22,"mg":0.384,"mv":-0.248},{"c":"22-70-030","n":"Llave de bola liviana PVC para roscar 2\" PCP","k":"Plomería","u":7.99,"q":726,"g":2.69,"mg":0.3373,"mv":0.705},{"c":"22-67-016","n":"Válvula check antirretorno de aguas residuales 4\" PCP","k":"Plomería","u":7.61,"q":210,"g":2.33,"mg":0.3055,"mv":0.059}],"cat":[{"c":"Plomería","v":330.55},{"c":"Material POP","v":1.82},{"c":"Exteriores","v":0.63}],"nArt":81,"tot":333.0,"totQ":186596,"totG":112.02},"rot":"Junio – Agosto 2026","meses":["6-2026","7-2026","8-2026"],"sup":[{"n":"CHARLY BELLO","v":111.8,"meta":77.27,"q":144.7},{"n":"CARLOS LAGARES","v":45.3,"meta":46.53,"q":97.3},{"n":"ALEJANDRO PRIETO","v":45.05,"meta":56.48,"q":79.8},{"n":"ALEJANDRO SAAVEDRA","v":41.49,"meta":41.37,"q":100.3},{"n":"LUIS LANDAETA","v":34.82,"meta":35.48,"q":98.1},{"n":"MARTIN SANTANDER","v":33.66,"meta":32.79,"q":102.6},{"n":"JESUS MUÑOZ","v":26.74,"meta":29.97,"q":89.2},{"n":"CARLOS GUANIPA","v":25.69,"meta":28.93,"q":88.8},{"n":"ELIAS JIMENEZ","v":22.35,"meta":21.5,"q":103.9},{"n":"JOSE ESTRELLA","v":17.07,"meta":19.15,"q":89.1},{"n":"TABARDO VILLASMIL","v":12.8,"meta":11.47,"q":111.6},{"n":"NELLY PATIÑO","v":8.33,"meta":12.63,"q":65.9},{"n":"DANIELA MASELLI","v":6.66,"meta":5.05,"q":132.0},{"n":"LIZMAR MARRERO","v":3.7,"meta":6.6,"q":56.1},{"n":"LUISA CABRERA","v":0.01,"meta":0.02,"q":57.2}],"est":[{"n":"Carabobo","v":108.42},{"n":"Zulia","v":52.41},{"n":"Distrito Capital","v":38.59},{"n":"Anzoátegui","v":30.24},{"n":"Aragua","v":26.38},{"n":"Bolívar","v":25.08},{"n":"Lara","v":24.51},{"n":"Miranda","v":20.86},{"n":"Portuguesa","v":13.33},{"n":"Nueva Esparta","v":12.8},{"n":"Barinas","v":12.44},{"n":"Monagas","v":11.21}],"reg":[{"n":"CENTRO","v":163.35},{"n":"Occidente","v":118.53},{"n":"Oriente","v":90.64},{"n":"Capital","v":62.93}],"cli0":[{"n":"FERRETERIA EPA, C.A.","v":102.48},{"n":"MI TIENDA VENEZUELA, C.A","v":12.43},{"n":"GRUPO ISO HOME, C.A","v":8.64},{"n":"FERRE KSA JH, C.A.","v":5.09},{"n":"GRUPO EMPRESARIAL VENTE, C.A","v":4.68},{"n":"FERROCERAMICA VALCRO,C.A.","v":4.64},{"n":"SERVIBOMBAS MARGARITA C.A","v":4.64},{"n":"FERRETERIA MATERIALES PUERTO FEMAPUERTO, C.A","v":4.2},{"n":"FERREMETALES LICCIONI, C.A","v":3.65},{"n":"FERREBOMBAS H FRIDEGOTTO, C.A","v":3.63},{"n":"FERREMATERIALES LA FUERTE, COMPAÑIA ANONIMA","v":3.28},{"n":"INVERSIONES DOBLE H.G, C.A","v":2.93},{"n":"FERRE TALIA C.A.","v":2.89},{"n":"FERRETERIA ARCI C.A.","v":2.87},{"n":"FAZ FERREAUTO ZULIA, C.A.","v":2.87}],"cli1":[{"n":"MI TIENDA VENEZUELA, C.A","v":12.43},{"n":"GRUPO ISO HOME, C.A","v":8.64},{"n":"FERRE KSA JH, C.A.","v":5.09},{"n":"GRUPO EMPRESARIAL VENTE, C.A","v":4.68},{"n":"FERROCERAMICA VALCRO,C.A.","v":4.64},{"n":"SERVIBOMBAS MARGARITA C.A","v":4.64},{"n":"FERRETERIA MATERIALES PUERTO FEMAPUERTO, C.A","v":4.2},{"n":"FERREMETALES LICCIONI, C.A","v":3.65},{"n":"FERREBOMBAS H FRIDEGOTTO, C.A","v":3.63},{"n":"FERREMATERIALES LA FUERTE, COMPAÑIA ANONIMA","v":3.28},{"n":"INVERSIONES DOBLE H.G, C.A","v":2.93},{"n":"FERRE TALIA C.A.","v":2.89},{"n":"FERRETERIA ARCI C.A.","v":2.87},{"n":"FAZ FERREAUTO ZULIA, C.A.","v":2.87},{"n":"DECORE MARGARITA C.A.","v":2.66}],"presup":425.25},"anio":{"0":{"art":[{"c":"22-13-007","n":"Canilla plástica 1/2 x 1/2\" 40 cm PCP","k":"Plomería","u":153.72,"q":224394,"g":40.66,"mg":0.2645,"mv":-0.056},{"c":"22-28-012","n":"Llave para manguera liviana PVC mango naranja 1/2\" PCP","k":"Plomería","u":135.31,"q":43038,"g":35.94,"mg":0.2656,"mv":-0.001},{"c":"22-70-019","n":"Llave de bola liviana PVC para roscar 1/2\" PCP","k":"Plomería","u":94.37,"q":80630,"g":27.05,"mg":0.2866,"mv":-0.032},{"c":"22-07-054","n":"Unión universal PVC para soldar 3/4\" PCP","k":"Plomería","u":91.42,"q":59964,"g":25.21,"mg":0.2757,"mv":0.326},{"c":"22-70-020","n":"Llave de bola liviana PVC para roscar 3/4\" PCP","k":"Plomería","u":77.72,"q":38026,"g":21.53,"mg":0.277,"mv":0.13},{"c":"22-70-028","n":"Llave de bola liviana PVC para soldar 1/2\" PCP","k":"Plomería","u":71.16,"q":63112,"g":18.55,"mg":0.2607,"mv":0.226},{"c":"22-13-008","n":"Canilla plástica 1/ 2 x 5/8\" 40 cm PCP","k":"Plomería","u":69.93,"q":104605,"g":17.12,"mg":0.2448,"mv":-0.141},{"c":"22-70-029","n":"Llave de bola liviana PVC para soldar 3/4\" PCP","k":"Plomería","u":67.15,"q":33847,"g":17.13,"mg":0.2551,"mv":0.27},{"c":"22-07-053","n":"Unión universal PVC para soldar 1/2\" PCP","k":"Plomería","u":63.36,"q":63203,"g":15.37,"mg":0.2425,"mv":0.285},{"c":"22-07-055","n":"Unión universal PVC para soldar 1\" PCP","k":"Plomería","u":49.29,"q":17394,"g":13.94,"mg":0.2828,"mv":0.109},{"c":"22-67-016","n":"Válvula check antirretorno de aguas residuales 4\" PCP","k":"Plomería","u":38.42,"q":996,"g":12.4,"mg":0.3227,"mv":2.278},{"c":"22-07-058","n":"Unión universal PVC para roscar 1/2\" PCP","k":"Plomería","u":37.38,"q":31407,"g":10.01,"mg":0.2679,"mv":-0.007},{"c":"22-07-059","n":"Unión universal PVC para roscar 3/4\" PCP","k":"Plomería","u":35.87,"q":21355,"g":10.0,"mg":0.2789,"mv":0.085},{"c":"22-13-009","n":"Canilla plástica 1/2 x 1/2\" 60 cm empaque individual PCP","k":"Plomería","u":34.51,"q":26666,"g":9.55,"mg":0.2768,"mv":-0.174},{"c":"22-70-021","n":"Llave de bola liviana PVC para roscar 1\" PCP","k":"Plomería","u":32.68,"q":9827,"g":9.82,"mg":0.3006,"mv":0.061}],"cat":[{"c":"Plomería","v":1452.87},{"c":"Exteriores","v":4.28},{"c":"Material POP","v":3.0}],"nArt":82,"tot":1460.15,"totQ":939559,"totG":408.94},"1":{"art":[{"c":"22-13-007","n":"Canilla plástica 1/2 x 1/2\" 40 cm PCP","k":"Plomería","u":124.22,"q":174482,"g":40.66,"mg":0.3273,"mv":0.009},{"c":"22-28-012","n":"Llave para manguera liviana PVC mango naranja 1/2\" PCP","k":"Plomería","u":108.1,"q":32818,"g":35.94,"mg":0.3324,"mv":0.174},{"c":"22-70-019","n":"Llave de bola liviana PVC para roscar 1/2\" PCP","k":"Plomería","u":73.96,"q":59466,"g":27.05,"mg":0.3657,"mv":0.047},{"c":"22-07-054","n":"Unión universal PVC para soldar 3/4\" PCP","k":"Plomería","u":66.09,"q":39837,"g":25.21,"mg":0.3814,"mv":0.329},{"c":"22-70-020","n":"Llave de bola liviana PVC para roscar 3/4\" PCP","k":"Plomería","u":65.23,"q":30590,"g":21.53,"mg":0.3301,"mv":0.248},{"c":"22-13-008","n":"Canilla plástica 1/ 2 x 5/8\" 40 cm PCP","k":"Plomería","u":54.11,"q":77946,"g":17.12,"mg":0.3164,"mv":-0.081},{"c":"22-70-029","n":"Llave de bola liviana PVC para soldar 3/4\" PCP","k":"Plomería","u":50.35,"q":23788,"g":17.13,"mg":0.3401,"mv":0.354},{"c":"22-70-028","n":"Llave de bola liviana PVC para soldar 1/2\" PCP","k":"Plomería","u":48.52,"q":39496,"g":18.55,"mg":0.3823,"mv":0.309},{"c":"22-67-016","n":"Válvula check antirretorno de aguas residuales 4\" PCP","k":"Plomería","u":38.42,"q":996,"g":12.4,"mg":0.3227,"mv":2.278},{"c":"22-07-053","n":"Unión universal PVC para soldar 1/2\" PCP","k":"Plomería","u":38.23,"q":34415,"g":15.37,"mg":0.4019,"mv":0.109},{"c":"22-07-055","n":"Unión universal PVC para soldar 1\" PCP","k":"Plomería","u":37.53,"q":12368,"g":13.94,"mg":0.3714,"mv":0.146},{"c":"22-07-059","n":"Unión universal PVC para roscar 3/4\" PCP","k":"Plomería","u":30.46,"q":17512,"g":10.0,"mg":0.3284,"mv":0.253},{"c":"22-07-058","n":"Unión universal PVC para roscar 1/2\" PCP","k":"Plomería","u":29.59,"q":23651,"g":10.01,"mg":0.3384,"mv":0.17},{"c":"22-70-021","n":"Llave de bola liviana PVC para roscar 1\" PCP","k":"Plomería","u":28.31,"q":8195,"g":9.82,"mg":0.347,"mv":0.174},{"c":"22-13-009","n":"Canilla plástica 1/2 x 1/2\" 60 cm empaque individual PCP","k":"Plomería","u":25.86,"q":18579,"g":9.55,"mg":0.3694,"mv":0.141}],"cat":[{"c":"Plomería","v":1211.59},{"c":"Exteriores","v":4.28},{"c":"Material POP","v":3.0}],"nArt":82,"tot":1218.87,"totQ":712212,"totG":408.94},"rot":"Septiembre 2025 – Agosto 2026","meses":["9-2025","10-2025","11-2025","12-2025","1-2026","2-2026","3-2026","4-2026","5-2026","6-2026","7-2026","8-2026"],"sup":[{"n":"CHARLY BELLO","v":265.32,"meta":188.95,"q":140.4},{"n":"ALEJANDRO PRIETO","v":193.94,"meta":138.12,"q":140.4},{"n":"CARLOS LAGARES","v":159.78,"meta":113.79,"q":140.4},{"n":"ALEJANDRO SAAVEDRA","v":142.05,"meta":101.16,"q":140.4},{"n":"LUIS LANDAETA","v":121.83,"meta":86.76,"q":140.4},{"n":"MARTIN SANTANDER","v":112.6,"meta":80.19,"q":140.4},{"n":"JESUS MUÑOZ","v":102.9,"meta":73.28,"q":140.4},{"n":"CARLOS GUANIPA","v":99.34,"meta":70.75,"q":140.4},{"n":"ELIAS JIMENEZ","v":73.84,"meta":52.59,"q":140.4},{"n":"JOSE ESTRELLA","v":65.75,"meta":46.82,"q":140.4},{"n":"NELLY PATIÑO","v":43.37,"meta":30.89,"q":140.4},{"n":"TABARDO VILLASMIL","v":39.4,"meta":28.06,"q":140.4},{"n":"LIZMAR MARRERO","v":22.66,"meta":16.14,"q":140.4},{"n":"DANIELA MASELLI","v":17.33,"meta":12.34,"q":140.4},{"n":"LUISA CABRERA","v":0.06,"meta":0.04,"q":140.4}],"est":[{"n":"Carabobo","v":357.99},{"n":"Zulia","v":209.67},{"n":"Anzoátegui","v":91.47},{"n":"Aragua","v":90.19},{"n":"Distrito Capital","v":89.83},{"n":"Miranda","v":88.3},{"n":"Lara","v":81.17},{"n":"Bolívar","v":76.42},{"n":"Barinas","v":51.73},{"n":"Mérida","v":41.18},{"n":"Sucre","v":41.08},{"n":"Nueva Esparta","v":39.4}],"reg":[{"n":"CENTRO","v":538.33},{"n":"Occidente","v":447.66},{"n":"Oriente","v":284.32},{"n":"Capital","v":189.85}],"cli0":[{"n":"FERRETERIA EPA, C.A.","v":241.27},{"n":"GRUPO ISO HOME, C.A","v":30.85},{"n":"MI TIENDA VENEZUELA, C.A","v":20.63},{"n":"FERRETERIA ARCI C.A.","v":20.62},{"n":"GRUPO EMPRESARIAL VENTE, C.A","v":19.37},{"n":"FERRETERIA Y PURIFICADORES TAMAYO,C.A.","v":13.02},{"n":"FERRE TALIA C.A.","v":12.86},{"n":"SERVIBOMBAS MARGARITA C.A","v":10.93},{"n":"CONCRETERA FERRECONOMICA 007, C.A","v":9.95},{"n":"INVERSIONES DOBLE H.G, C.A","v":8.83},{"n":"FERREBOMBAS H FRIDEGOTTO, C.A","v":8.72},{"n":"MI TIENDA VENEZUELA, C.A.","v":8.53},{"n":"COMERCIAL FERRETERO EL GOCHO C.A","v":7.34},{"n":"FERRE KSA JH, C.A.","v":7.32},{"n":"DECORE MARGARITA C.A.","v":7.26}],"cli1":[{"n":"GRUPO ISO HOME, C.A","v":30.85},{"n":"MI TIENDA VENEZUELA, C.A","v":20.63},{"n":"FERRETERIA ARCI C.A.","v":20.62},{"n":"GRUPO EMPRESARIAL VENTE, C.A","v":19.37},{"n":"FERRETERIA Y PURIFICADORES TAMAYO,C.A.","v":13.02},{"n":"FERRE TALIA C.A.","v":12.86},{"n":"SERVIBOMBAS MARGARITA C.A","v":10.93},{"n":"CONCRETERA FERRECONOMICA 007, C.A","v":9.95},{"n":"INVERSIONES DOBLE H.G, C.A","v":8.83},{"n":"FERREBOMBAS H FRIDEGOTTO, C.A","v":8.72},{"n":"MI TIENDA VENEZUELA, C.A.","v":8.53},{"n":"COMERCIAL FERRETERO EL GOCHO C.A","v":7.34},{"n":"FERRE KSA JH, C.A.","v":7.32},{"n":"DECORE MARGARITA C.A.","v":7.26},{"n":"FERRETERIA LA CARABOBEÑA C.A","v":7.12}],"presup":1039.87}},"ped":[{"c":"22-70-033","n":"Llave de bola liviana PVC para roscar 1 1/2\" PCP","d":194.0,"st":43.0,"tr":264.0,"cb":1.6,"sg":276.0,"ct":5.2111},{"c":"22-70-031","n":"Llave de bola liviana PVC para soldar 2\" PCP","d":92.0,"st":0,"tr":112.0,"cb":1.2,"sg":163.0,"ct":7.4834},{"c":"22-67-055","n":"Llave de bola liviana manija larga PVC para roscar 3\" PCP","d":23.0,"st":0,"tr":30.0,"cb":1.3,"sg":40.0,"ct":23.2957},{"c":"22-07-056","n":"Unión universal PVC para soldar 1 1/2\" PCP","d":269.0,"st":1.0,"tr":648.0,"cb":2.4,"sg":159.0,"ct":4.8781},{"c":"22-28-013","n":"Llave para manguera pesada PVC mango azul 1/2\" PCP","d":84.0,"st":24.0,"tr":144.0,"cb":2.0,"sg":84.0,"ct":6.9256},{"c":"33-07-058","n":"Exhibidor cajas apilables PCP","d":160.0,"st":0,"tr":0,"cb":0.0,"sg":481.0,"ct":null},{"c":"22-07-065","n":"Unión universal PVC para soldar 3\" PCP","d":19.0,"st":7.0,"tr":30.0,"cb":1.9,"sg":21.0,"ct":18.362},{"c":"22-70-084","n":"Llave de bola liviana manija larga PVC para roscar 1\" PCP","d":186.0,"st":0,"tr":432.0,"cb":2.3,"sg":127.0,"ct":2.4357},{"c":"22-70-023","n":"Llave de bola pesada PVC para roscar 1/2\" PCP","d":314.0,"st":0,"tr":768.0,"cb":2.4,"sg":174.0,"ct":1.7033},{"c":"22-07-066","n":"Unión universal PVC para soldar 4\" PCP","d":11.0,"st":26.0,"tr":0,"cb":2.3,"sg":7.0,"ct":24.5023},{"c":"22-07-061","n":"Unión universal PVC para roscar 1 1/2\" PCP","d":76.0,"st":0,"tr":200.0,"cb":2.6,"sg":29.0,"ct":4.9332},{"c":"22-07-062","n":"Unión universal PVC para roscar 2\" PCP","d":52.0,"st":53.0,"tr":80.0,"cb":2.6,"sg":22.0,"ct":6.0302},{"c":"33-07-228","n":"Taza Pequeña de policarbonato 120 cc PCP","d":43.0,"st":0,"tr":0,"cb":0.0,"sg":129.0,"ct":null},{"c":"33-07-229","n":"Jarra Hermética 2.5lts PCP","d":17.0,"st":0,"tr":0,"cb":0.0,"sg":51.0,"ct":null},{"c":"22-67-063","n":"Válvula de bola doble unión universal PVC semipesada para soldar 3/4\" PCP","d":54.0,"st":155.0,"tr":0,"cb":2.9,"sg":7.0,"ct":4.2932}],"brand":[{"m":"8-2023","usd":43.56,"un":41866,"co":12.06,"inv":111.3,"pr":0.06},{"m":"9-2023","usd":61.97,"un":60600,"co":13.2,"inv":192.6,"pr":0.06},{"m":"10-2023","usd":74.76,"un":61771,"co":17.21,"inv":135.1,"pr":0.06},{"m":"11-2023","usd":69.36,"un":57706,"co":16.27,"inv":152.1,"pr":0.07},{"m":"12-2023","usd":79.8,"un":72629,"co":16.64,"inv":151.2,"pr":0.04},{"m":"1-2024","usd":87.5,"un":86222,"co":21.14,"inv":84.9,"pr":0.05},{"m":"2-2024","usd":36.5,"un":36020,"co":9.59,"inv":58.0,"pr":0.06},{"m":"3-2024","usd":164.47,"un":154351,"co":34.73,"inv":85.2,"pr":0.1},{"m":"4-2024","usd":56.92,"un":40770,"co":15.28,"inv":43.6,"pr":0.1},{"m":"5-2024","usd":98.56,"un":74390,"co":27.76,"inv":77.5,"pr":0.1},{"m":"6-2024","usd":100.52,"un":88513,"co":24.88,"inv":171.9,"pr":0.09},{"m":"7-2024","usd":83.94,"un":68967,"co":23.5,"inv":98.7,"pr":0.12},{"m":"8-2024","usd":58.84,"un":40362,"co":21.15,"inv":61.0,"pr":0.1},{"m":"9-2024","usd":111.42,"un":85797,"co":36.4,"inv":149.6,"pr":0.1},{"m":"10-2024","usd":127.41,"un":109201,"co":38.68,"inv":232.3,"pr":0.1},{"m":"11-2024","usd":100.69,"un":70824,"co":34.26,"inv":163.4,"pr":0.12},{"m":"12-2024","usd":49.34,"un":33277,"co":16.22,"inv":213.8,"pr":0.07},{"m":"1-2025","usd":108.49,"un":70035,"co":38.75,"inv":143.1,"pr":0.08},{"m":"2-2025","usd":140.37,"un":118759,"co":36.82,"inv":79.1,"pr":0.14},{"m":"3-2025","usd":71.57,"un":50095,"co":25.53,"inv":134.9,"pr":0.1},{"m":"4-2025","usd":138.78,"un":89347,"co":53.66,"inv":195.6,"pr":0.18},{"m":"5-2025","usd":91.1,"un":59977,"co":34.55,"inv":251.9,"pr":0.11},{"m":"6-2025","usd":122.61,"un":88369,"co":38.17,"inv":167.7,"pr":0.21},{"m":"7-2025","usd":104.84,"un":73055,"co":30.04,"inv":172.2,"pr":0.14},{"m":"8-2025","usd":140.98,"un":102000,"co":37.69,"inv":204.8,"pr":0.18},{"m":"9-2025","usd":117.74,"un":75217,"co":30.79,"inv":117.4,"pr":0.12},{"m":"10-2025","usd":100.81,"un":61540,"co":32.21,"inv":105.7,"pr":0.13},{"m":"11-2025","usd":168.96,"un":130726,"co":43.47,"inv":149.3,"pr":0.12},{"m":"12-2025","usd":52.03,"un":23949,"co":17.48,"inv":203.3,"pr":0.0},{"m":"1-2026","usd":104.06,"un":71781,"co":28.5,"inv":395.8,"pr":110.25},{"m":"2-2026","usd":110.76,"un":77803,"co":29.04,"inv":293.3,"pr":126.0},{"m":"3-2026","usd":129.87,"un":78654,"co":42.45,"inv":208.1,"pr":126.0},{"m":"4-2026","usd":147.81,"un":87991,"co":46.07,"inv":265.1,"pr":126.0},{"m":"5-2026","usd":92.66,"un":54459,"co":26.98,"inv":192.9,"pr":126.0},{"m":"6-2026","usd":142.21,"un":96079,"co":35.81,"inv":175.4,"pr":141.75},{"m":"7-2026","usd":147.54,"un":93497,"co":38.03,"inv":160.2,"pr":141.75},{"m":"8-2026","usd":145.7,"un":87863,"co":38.17,"inv":118.7,"pr":141.75},{"m":"9-2026","usd":29.52,"un":16066,"co":6.49,"inv":93.7,"pr":141.75}],"epaMes":{"8-2023":4.8,"9-2023":5.36,"12-2023":34.24,"1-2024":9.56,"3-2024":61.55,"5-2024":0.89,"6-2024":31.15,"7-2024":13.42,"8-2024":-9.75,"9-2024":19.04,"10-2024":34.3,"11-2024":8.25,"12-2024":0.98,"1-2025":14.06,"2-2025":65.42,"3-2025":5.96,"4-2025":33.71,"5-2025":-0.0,"6-2025":33.56,"7-2025":24.5,"8-2025":50.28,"9-2025":24.27,"10-2025":5.47,"11-2025":50.51,"12-2025":-0.0,"1-2026":23.86,"2-2026":24.14,"3-2026":-0.0,"4-2026":-0.01,"5-2026":10.54,"6-2026":45.0,"7-2026":28.76,"8-2026":28.72,"9-2026":9.03},"act":{"8-2025":627,"9-2025":587,"10-2025":622,"11-2025":924,"12-2025":424,"1-2026":607,"2-2026":672,"3-2026":807,"4-2026":846,"5-2026":650,"6-2026":682,"7-2026":735,"8-2026":728,"9-2026":253},"inact":{"8-2025":8006,"9-2025":8046,"10-2025":8011,"11-2025":7709,"12-2025":8209,"1-2026":8026,"2-2026":7961,"3-2026":7826,"4-2026":7787,"5-2026":7983,"6-2026":7951,"7-2026":7898,"8-2026":7905,"9-2026":8380},"parcial":"9-2026","kgUnid":2.3901,"ocTotal":390.07,"nSku":56};

const PERIODOS = [
  { id: "mes", label: "Este mes" },
  { id: "trimestre", label: "Último trimestre" },
  { id: "anio", label: "Año actual" },
];

/* ── Formato ── */
const fUSD = (v) => v == null ? "—" : Math.abs(v) >= 1000
  ? "$" + (v / 1000).toFixed(2) + "M" : "$" + v.toFixed(1) + "K";
const fFull = (v) => v == null ? "—" : "$" + Math.round(v * 1000).toLocaleString("es-VE");
const fNum = (v, d = 0) => v == null ? "—" : v.toLocaleString("es-VE", { maximumFractionDigits: d });
const fPct = (v, d = 1) => v == null ? "—" : (v * 100).toFixed(d) + "%";
const iniciales = (n) => n.split(" ").slice(0, 2).map((p) => p[0]).join("");
const mesIdx = (m) => { const p = m.split("-"); return +p[1] * 12 + (+p[0] - 1); };
const mesCorto = (m) => {
  const p = m.split("-");
  return ["Ene","Feb","Mar","Abr","May","Jun","Jul","Ago","Sep","Oct","Nov","Dic"][+p[0]-1] + " " + p[1].slice(2);
};

/* ── Pronóstico Holt-Winters aditivo ── */
function holtWinters(y, m = 12, h = 3) {
  const n = y.length;
  if (n < 2 * m) return null;
  const L0 = y.slice(0, m).reduce((a, b) => a + b, 0) / m;
  const S0 = y.slice(0, m).map((v) => v - L0);
  let best = null;
  const R = [0.05, 0.15, 0.3, 0.5, 0.75];
  for (const a of R) for (const b of [0.01, 0.05, 0.15]) for (const g of R) {
    let L = L0;
    let T = (y.slice(m, 2 * m).reduce((x, z) => x + z, 0) - y.slice(0, m).reduce((x, z) => x + z, 0)) / (m * m);
    const S = S0.slice(); let sse = 0;
    for (let i = 0; i < n; i++) {
      const s = S[i % m];
      sse += (y[i] - (L + T + s)) ** 2;
      const Lp = L;
      L = a * (y[i] - s) + (1 - a) * (L + T);
      T = b * (L - Lp) + (1 - b) * T;
      S[i % m] = g * (y[i] - L) + (1 - g) * s;
    }
    if (!best || sse < best.sse) best = { sse, L, T, S, n };
  }
  const out = [];
  for (let k = 1; k <= h; k++) out.push(Math.max(0, best.L + k * best.T + best.S[(best.n + k - 1) % m]));
  return { vals: out, metodo: "Holt-Winters con estacionalidad", rmse: Math.sqrt(best.sse / n) };
}
function mediaPond(y, h = 3) {
  const k = Math.min(6, y.length), u = y.slice(-k), w = u.map((_, i) => i + 1);
  const sw = w.reduce((a, b) => a + b, 0);
  const base = u.reduce((a, v, i) => a + v * w[i], 0) / sw;
  let t = 0;
  if (y.length >= 6) t = (y.slice(-3).reduce((a, b) => a + b, 0) / 3 - y.slice(-6, -3).reduce((a, b) => a + b, 0) / 3) / 3;
  return { vals: Array.from({ length: h }, (_, i) => Math.max(0, base + t * (i + 1))),
           metodo: "Promedio ponderado con tendencia",
           rmse: Math.sqrt(u.reduce((a, v) => a + (v - base) ** 2, 0) / k) };
}

const ESTADOS = {
  meta:    { t: "En meta",   txt: "text-emerald-300", dot: "bg-emerald-400", g: "from-emerald-400 to-teal-400" },
  riesgo:  { t: "En riesgo", txt: "text-amber-300",   dot: "bg-amber-400",   g: "from-amber-400 to-orange-400" },
  critico: { t: "Crítico",   txt: "text-rose-300",    dot: "bg-rose-400",    g: "from-rose-400 to-pink-500" },
};
const TONOS = ["#0ea5e9", "#8b5cf6", "#10b981", "#f59e0b", "#f43f5e", "#06b6d4", "#a855f7", "#14b8a6"];

/* ── Piezas ── */
function Sparkline({ data, color }) {
  const d = data.map((v, i) => ({ i, v }));
  const id = "sp" + color.slice(1);
  return (
    <ResponsiveContainer width="100%" height={38}>
      <AreaChart data={d} margin={{ top: 2, right: 0, left: 0, bottom: 0 }}>
        <defs>
          <linearGradient id={id} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor={color} stopOpacity={0.45} />
            <stop offset="100%" stopColor={color} stopOpacity={0} />
          </linearGradient>
        </defs>
        <Area type="monotone" dataKey="v" stroke={color} strokeWidth={1.75}
              fill={"url(#" + id + ")"} dot={false} isAnimationActive={false} />
      </AreaChart>
    </ResponsiveContainer>
  );
}

function Kpi({ icono: I, etiqueta, valor, sub, delta, spark, color, acento }) {
  const sube = delta != null && delta >= 0;
  return (
    <div className="relative overflow-hidden rounded-2xl border border-slate-800 bg-slate-900 p-5 shadow-xl">
      <div className="absolute inset-x-0 top-0 h-px"
           style={{ background: "linear-gradient(90deg,transparent," + color + ",transparent)" }} />
      <div className="flex items-start justify-between gap-2">
        <div className="flex items-center gap-2.5">
          <div className="grid h-9 w-9 place-items-center rounded-xl"
               style={{ background: acento, boxShadow: "0 0 0 1px " + color + "33" }}>
            <I size={17} style={{ color }} strokeWidth={2.1} />
          </div>
          <span className="text-xs font-medium text-slate-400">{etiqueta}</span>
        </div>
        {delta != null && (
          <span className={"flex shrink-0 items-center gap-1 rounded-lg px-2 py-1 text-xs font-semibold " +
            (sube ? "bg-emerald-500 text-emerald-950" : "bg-rose-500 text-rose-950")}>
            {sube ? <ArrowUpRight size={12} strokeWidth={2.6} /> : <ArrowDownRight size={12} strokeWidth={2.6} />}
            {sube ? "+" : ""}{delta.toFixed(1)}%
          </span>
        )}
      </div>
      <div className="mt-4 flex items-end justify-between gap-4">
        <div className="min-w-0">
          <div className="truncate text-3xl font-semibold tracking-tight text-white">{valor}</div>
          <div className="mt-1 text-xs text-slate-500">{sub}</div>
        </div>
        <div className="w-24 shrink-0 opacity-90"><Sparkline data={spark} color={color} /></div>
      </div>
    </div>
  );
}

function Tarjeta({ titulo, sub, extra, children, className = "" }) {
  return (
    <section className={"rounded-2xl border border-slate-800 bg-slate-900 shadow-xl " + className}>
      <header className="flex flex-wrap items-start justify-between gap-3 px-6 pt-5">
        <div>
          <h2 className="text-sm font-semibold text-white">{titulo}</h2>
          {sub && <p className="mt-0.5 text-xs text-slate-500">{sub}</p>}
        </div>
        {extra}
      </header>
      <div className="px-6 pb-6 pt-4">{children}</div>
    </section>
  );
}

function TipHero({ active, payload, label }) {
  if (!active || !payload?.length) return null;
  return (
    <div className="rounded-xl border border-slate-700 bg-slate-950 px-3 py-2 shadow-2xl">
      <div className="mb-1 text-xs font-medium text-slate-300">{label}</div>
      {payload.filter((p) => p.value != null).map((p) => (
        <div key={p.dataKey} className="flex items-center gap-2 text-xs">
          <span className="h-2 w-2 rounded-full" style={{ background: p.color }} />
          <span className="text-slate-400">{p.dataKey === "real" ? "Venta real" : "Pronóstico"}</span>
          <span className="ml-auto font-semibold text-white">{fFull(p.value)}</span>
        </div>
      ))}
    </div>
  );
}

/* ── App ── */
export default function App() {
  const [periodo, setPeriodo] = useState("mes");
  const [conEpa, setConEpa] = useState(true);
  const [abierto, setAbierto] = useState(false);
  const eKey = conEpa ? "0" : "1";

  /* Serie mensual de la marca, con o sin EPA */
  const serie = useMemo(() => D.brand.map((b) => {
    const e = conEpa ? 0 : (D.epaMes[b.m] || 0);
    return { ...b, usd: +(b.usd - e).toFixed(3), etiq: mesCorto(b.m), parcial: b.m === D.parcial };
  }), [conEpa]);

  const cerrada = serie.filter((s) => !s.parcial);
  const pron = useMemo(() => {
    const y = cerrada.map((s) => s.usd);
    return holtWinters(y, 12, 3) || mediaPond(y, 3);
  }, [cerrada]);

  /* Datos del gráfico héroe: últimos 18 meses + 3 de pronóstico */
  const hero = useMemo(() => {
    const base = serie.slice(-18).map((s) => ({ etiq: s.etiq, real: s.usd }));
    const ultIdx = mesIdx(D.brand[D.brand.length - 1].m);
    const fut = pron.vals.map((v, i) => {
      const t = ultIdx + i + 1;
      return { etiq: mesCorto(((t % 12) + 1) + "-" + Math.floor(t / 12)), pron: +v.toFixed(2) };
    });
    base[base.length - 1] = { ...base[base.length - 1], pron: base[base.length - 1].real };
    return [...base, ...fut];
  }, [serie, pron]);

  const P = D.per[periodo];
  const E = P[eKey];
  const nm = P.meses.length;

  /* Comparación contra el mismo período del año anterior */
  const yoy = useMemo(() => {
    const map = Object.fromEntries(serie.map((s) => [s.m, s.usd]));
    const prev = P.meses.map((m) => { const p = m.split("-"); return p[0] + "-" + (+p[1] - 1); });
    const a = P.meses.reduce((x, m) => x + (map[m] || 0), 0);
    const b = prev.reduce((x, m) => x + (map[m] || 0), 0);
    return b > 0 ? a / b - 1 : null;
  }, [serie, P]);

  const cumpl = P.presup ? E.tot / P.presup : null;
  const ultCerrada = cerrada[cerrada.length - 1];
  const cierre = pron.vals[0];
  const margen = E.tot ? E.totG / E.tot : null;
  const precioU = E.totQ ? (E.tot * 1000) / E.totQ : null;
  const toneladas = (E.totQ * D.kgUnid) / 1000;
  const spark = serie.slice(-7).map((s) => s.usd);
  const sparkU = serie.slice(-7).map((s) => s.un / 1000);
  const mesAct = P.meses[P.meses.length - 1];
  const activos = D.act[mesAct], inactivos = D.inact[mesAct];
  const maxArt = Math.max(...E.art.map((a) => a.u));
  const cliRank = P["cli" + eKey];
  const totCli = cliRank.reduce((a, c) => a + c.v, 0);

  return (
    <div className="min-h-screen bg-slate-950 text-slate-200"
         style={{ fontFamily: "ui-sans-serif, system-ui, -apple-system, 'Segoe UI', sans-serif" }}>
      <div className="pointer-events-none fixed inset-0"
           style={{ background:
             "radial-gradient(720px circle at 12% -8%, rgba(56,189,248,.10), transparent 55%)," +
             "radial-gradient(620px circle at 88% 4%, rgba(139,92,246,.09), transparent 55%)" }} />

      <div className="relative">
        {/* Barra superior */}
        <header className="sticky top-0 z-30 border-b border-slate-800"
                style={{ background: "rgba(2,6,23,.82)", backdropFilter: "blur(14px)" }}>
          <div className="mx-auto flex max-w-[1500px] flex-wrap items-center gap-4 px-6 py-3.5">
            <div className="flex items-center gap-3">
              <div className="grid h-9 w-9 place-items-center rounded-xl font-bold text-slate-950"
                   style={{ background: "linear-gradient(135deg,#38bdf8,#6366f1)" }}>F</div>
              <div className="leading-tight">
                <div className="text-sm font-semibold tracking-wide text-white">FEBECA</div>
                <div className="text-xs text-slate-500">Compras · marca PCP</div>
              </div>
            </div>

            <div className="flex items-center gap-2 rounded-full border border-slate-800 px-3 py-1.5"
                 style={{ background: "rgba(16,185,129,.07)" }}>
              <span className="relative flex h-2 w-2">
                <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-emerald-400 opacity-60" />
                <span className="relative inline-flex h-2 w-2 rounded-full bg-emerald-400" />
              </span>
              <span className="text-xs font-medium text-emerald-300">Datos del SIM</span>
              <span className="text-xs text-slate-600">· cierre {mesCorto(D.brand[D.brand.length - 2].m)}</span>
            </div>

            <div className="ml-auto flex flex-wrap items-center gap-3">
              <button onClick={() => setConEpa((v) => !v)}
                      className={"flex items-center gap-2 rounded-xl border px-3.5 py-2 text-sm font-medium " +
                        (conEpa ? "border-amber-500 bg-slate-900 text-amber-300" : "border-slate-800 bg-slate-900 text-slate-400")}>
                <span className={"h-2 w-2 rounded-full " + (conEpa ? "bg-amber-400" : "bg-slate-600")} />
                {conEpa ? "EPA incluido" : "EPA excluido"}
              </button>

              <div className="relative">
                <button onClick={() => setAbierto((v) => !v)}
                        className="flex items-center gap-2 rounded-xl border border-slate-800 bg-slate-900 px-3.5 py-2 text-sm font-medium text-slate-200 hover:border-slate-700">
                  {PERIODOS.find((p) => p.id === periodo).label}
                  <ChevronDown size={15} className="text-slate-500" />
                </button>
                {abierto && (
                  <div className="absolute right-0 z-40 mt-2 w-48 overflow-hidden rounded-xl border border-slate-800 bg-slate-900 shadow-2xl">
                    {PERIODOS.map((p) => (
                      <button key={p.id} onClick={() => { setPeriodo(p.id); setAbierto(false); }}
                              className={"flex w-full items-center justify-between px-4 py-2.5 text-left text-sm hover:bg-slate-800 " +
                                (p.id === periodo ? "text-sky-300" : "text-slate-300")}>
                        {p.label}
                        {p.id === periodo && <Circle size={7} fill="currentColor" strokeWidth={0} />}
                      </button>
                    ))}
                  </div>
                )}
              </div>

              <button className="relative grid h-9 w-9 place-items-center rounded-xl border border-slate-800 bg-slate-900 text-slate-400 hover:text-slate-200">
                <Bell size={16} />
                <span className="absolute right-2 top-2 h-1.5 w-1.5 rounded-full bg-rose-400" />
              </button>

              <div className="flex items-center gap-2.5 rounded-xl border border-slate-800 bg-slate-900 py-1.5 pl-1.5 pr-3.5">
                <div className="grid h-7 w-7 place-items-center rounded-lg text-xs font-bold text-white"
                     style={{ background: "linear-gradient(135deg,#8b5cf6,#d946ef)" }}>JG</div>
                <div className="leading-tight">
                  <div className="text-xs font-medium text-white">José G.</div>
                  <div className="text-[11px] text-slate-500">Compras intl.</div>
                </div>
              </div>
            </div>
          </div>
        </header>

        <main className="mx-auto max-w-[1500px] px-6 py-7">
          <div className="mb-6 flex flex-wrap items-end justify-between gap-3">
            <div>
              <h1 className="text-2xl font-semibold tracking-tight text-white">PCP · resumen de marca</h1>
              <p className="mt-1 text-sm text-slate-500">
                {P.rot} · {E.nArt} artículos con movimiento · {P.sup.length} supervisores
              </p>
            </div>
            <div className="flex flex-wrap gap-2 text-xs">
              {[["Inventario", fUSD(ultCerrada.inv), Boxes],
                ["En tránsito", fUSD(D.ocTotal), Truck],
                ["SKU con stock", fNum(D.nSku), Package],
                ["Clientes activos", fNum(activos), Users]].map(([t, v, I]) => (
                <div key={t} className="flex items-center gap-2 rounded-xl border border-slate-800 bg-slate-900 px-3.5 py-2">
                  <I size={14} className="text-slate-500" />
                  <span className="text-slate-500">{t}</span>
                  <span className="font-semibold text-slate-200">{v}</span>
                </div>
              ))}
            </div>
          </div>

          {/* KPIs */}
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
            <Kpi icono={DollarSign} etiqueta="Venta neta" valor={fUSD(E.tot)}
                 sub={fFull(E.tot)} delta={yoy != null ? yoy * 100 : null} spark={spark}
                 color="#38bdf8" acento="rgba(56,189,248,.12)" />
            <Kpi icono={TrendingUp} etiqueta="Pronóstico próximo mes" valor={fUSD(cierre)}
                 sub={pron.metodo} delta={ultCerrada.usd ? (cierre / ultCerrada.usd - 1) * 100 : null}
                 spark={spark} color="#22d3ee" acento="rgba(34,211,238,.12)" />
            <Kpi icono={Target} etiqueta="Cumplimiento de presupuesto" valor={fPct(cumpl)}
                 sub={"Meta " + fUSD(P.presup)} delta={cumpl != null ? (cumpl - 1) * 100 : null}
                 spark={serie.slice(-7).map((s) => s.pr ? s.usd / s.pr * 100 : 0)}
                 color={cumpl >= 1 ? "#34d399" : "#fbbf24"}
                 acento={cumpl >= 1 ? "rgba(52,211,153,.12)" : "rgba(251,191,36,.12)"} />
            <Kpi icono={Package} etiqueta="Volumen despachado" valor={fNum(E.totQ / 1000, 1) + "K u."}
                 sub={fNum(toneladas, 1) + " toneladas · $" + (precioU || 0).toFixed(2) + " por unidad"}
                 delta={null} spark={sparkU} color="#a78bfa" acento="rgba(167,139,250,.12)" />
          </div>

          {/* Héroe + regiones */}
          <div className="mt-5 grid grid-cols-1 gap-5 lg:grid-cols-3">
            <Tarjeta className="lg:col-span-2" titulo="Pronóstico de ventas"
                     sub={pron.metodo + " · error típico " + fUSD(pron.rmse) + " · " + cerrada.length + " meses de historia"}
                     extra={
                       <div className="flex items-center gap-4 text-xs">
                         <span className="flex items-center gap-1.5 text-slate-400">
                           <span className="h-0.5 w-5 rounded" style={{ background: "#38bdf8" }} />Real
                         </span>
                         <span className="flex items-center gap-1.5 text-slate-400">
                           <span className="h-0.5 w-5 rounded"
                                 style={{ background: "repeating-linear-gradient(90deg,#22d3ee 0 5px,transparent 5px 9px)" }} />
                           Pronóstico
                         </span>
                       </div>
                     }>
              <ResponsiveContainer width="100%" height={330}>
                <ComposedChart data={hero} margin={{ top: 10, right: 8, left: -8, bottom: 0 }}>
                  <defs>
                    <linearGradient id="gReal" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="0%" stopColor="#38bdf8" stopOpacity={0.42} />
                      <stop offset="100%" stopColor="#38bdf8" stopOpacity={0.02} />
                    </linearGradient>
                  </defs>
                  <CartesianGrid stroke="#1e293b" vertical={false} />
                  <XAxis dataKey="etiq" tick={{ fontSize: 10, fill: "#64748b" }}
                         axisLine={{ stroke: "#1e293b" }} tickLine={false} interval="preserveStartEnd" />
                  <YAxis tick={{ fontSize: 11, fill: "#64748b" }} axisLine={false} tickLine={false}
                         tickFormatter={(v) => "$" + v.toFixed(0) + "K"} />
                  <Tooltip content={<TipHero />} cursor={{ stroke: "#334155", strokeWidth: 1 }} />
                  <Area type="monotone" dataKey="real" stroke="#38bdf8" strokeWidth={2.4} fill="url(#gReal)"
                        dot={false} activeDot={{ r: 5, fill: "#38bdf8", stroke: "#020617", strokeWidth: 2 }} />
                  <Line type="monotone" dataKey="pron" stroke="#22d3ee" strokeWidth={2.4} strokeDasharray="6 5"
                        dot={{ r: 3.5, fill: "#22d3ee", stroke: "#020617", strokeWidth: 2 }} connectNulls />
                </ComposedChart>
              </ResponsiveContainer>
              <p className="mt-2 text-xs text-slate-600">
                El último punto real es {mesCorto(D.parcial)}, que va incompleto y queda fuera del modelo.
              </p>
            </Tarjeta>

            <Tarjeta titulo="Venta por región" sub="Reparto geográfico del período">
              <div className="space-y-3.5">
                {P.reg.map((rg, i) => {
                  const total = P.reg.reduce((a, x) => a + x.v, 0);
                  return (
                    <div key={rg.n}>
                      <div className="mb-1.5 flex items-baseline justify-between text-xs">
                        <span className="font-medium capitalize text-slate-200">{rg.n.toLowerCase()}</span>
                        <span className="flex items-center gap-2">
                          <span className="text-slate-400">{fUSD(rg.v)}</span>
                          <span className="font-semibold text-sky-300">{fPct(rg.v / total, 0)}</span>
                        </span>
                      </div>
                      <div className="h-1.5 overflow-hidden rounded-full bg-slate-800">
                        <div className="h-full rounded-full"
                             style={{ width: (rg.v / P.reg[0].v) * 100 + "%",
                                      background: "linear-gradient(90deg,hsl(" + (200 + i * 18) + " 90% 62%),hsl(" + (228 + i * 18) + " 85% 58%))",
                                      transition: "width .45s ease" }} />
                      </div>
                    </div>
                  );
                })}
              </div>

              <div className="mt-5 space-y-2">
                <div className="text-xs font-medium text-slate-400">Estados principales</div>
                {P.est.slice(0, 5).map((e) => (
                  <div key={e.n} className="flex items-center justify-between text-xs">
                    <span className="text-slate-400">{e.n}</span>
                    <span className="font-medium text-slate-200">{fUSD(e.v)}</span>
                  </div>
                ))}
              </div>

              <div className="mt-5 rounded-xl border border-slate-800 p-3.5" style={{ background: "rgba(56,189,248,.05)" }}>
                <div className="flex gap-2 text-xs text-slate-400">
                  <Activity size={13} className="mt-0.5 shrink-0 text-sky-400" />
                  <span>Carabobo concentra {fPct(P.est[0].v / P.est.reduce((a, x) => a + x.v, 0), 0)} de la venta. Región Centro manda el negocio.</span>
                </div>
              </div>
            </Tarjeta>
          </div>

          {/* Supervisores + artículos */}
          <div className="mt-5 grid grid-cols-1 gap-5 lg:grid-cols-5">
            <Tarjeta className="lg:col-span-3" titulo="Rendimiento comercial"
                     sub="Supervisores contra su presupuesto proporcional"
                     extra={
                       <div className="flex flex-wrap gap-3 text-xs">
                         {Object.entries(ESTADOS).map(([k, e]) => (
                           <span key={k} className="flex items-center gap-1.5 text-slate-500">
                             <span className={"h-2 w-2 rounded-full " + e.dot} />{e.t}
                           </span>
                         ))}
                       </div>
                     }>
              <div className="space-y-3">
                {P.sup.slice(0, 8).map((s, i) => {
                  const q = s.q || 0;
                  const e = ESTADOS[q >= 100 ? "meta" : q >= 80 ? "riesgo" : "critico"];
                  return (
                    <div key={s.n} className="flex items-center gap-3.5 rounded-xl border border-slate-800 p-3"
                         style={{ background: "rgba(15,23,42,.6)" }}>
                      <div className="grid h-10 w-10 shrink-0 place-items-center rounded-xl text-xs font-bold text-white"
                           style={{ backgroundImage: "linear-gradient(135deg," + TONOS[i % TONOS.length] + ",#1e293b)" }}>
                        {iniciales(s.n)}
                      </div>
                      <div className="min-w-0 flex-1">
                        <div className="flex items-baseline justify-between gap-3">
                          <span className="truncate text-sm font-medium capitalize text-white">{s.n.toLowerCase()}</span>
                          <span className="shrink-0 text-xs text-slate-500">{fUSD(s.v)}</span>
                        </div>
                        <div className="mt-1.5 flex items-center gap-3">
                          <div className="h-1.5 flex-1 overflow-hidden rounded-full bg-slate-800">
                            <div className={"h-full rounded-full bg-gradient-to-r " + e.g}
                                 style={{ width: Math.min(100, q) + "%", transition: "width .45s ease" }} />
                          </div>
                          <span className="w-12 shrink-0 text-right text-xs font-semibold text-slate-300">{q.toFixed(0)}%</span>
                        </div>
                        <div className="mt-1 text-[11px] text-slate-600">Meta {fUSD(s.meta)}</div>
                      </div>
                      <span className={"shrink-0 rounded-lg border px-2.5 py-1 text-[11px] font-semibold " + e.txt}
                            style={{ borderColor: "currentColor" }}>{e.t}</span>
                    </div>
                  );
                })}
              </div>
              <div className="mt-4 flex gap-2 rounded-xl border border-slate-800 p-3 text-xs text-slate-500"
                   style={{ background: "rgba(245,158,11,.05)" }}>
                <AlertTriangle size={13} className="mt-0.5 shrink-0 text-amber-400" />
                <span>
                  En PCP la venta no viene asignada por vendedor: el SIM la reporta como «no clasificado».
                  Por eso el ranking va por supervisor. El botón de EPA tampoco aplica en este corte.
                </span>
              </div>
            </Tarjeta>

            <Tarjeta className="lg:col-span-2" titulo="Top de artículos"
                     sub={"Venta del período" + (conEpa ? "" : ", sin EPA")}>
              <ResponsiveContainer width="100%" height={300}>
                <BarChart data={E.art.slice(0, 8).map((a) => ({ ...a, corto: a.n.slice(0, 26) })).reverse()}
                          layout="vertical" margin={{ left: 6, right: 26, top: 0, bottom: 0 }}>
                  <CartesianGrid stroke="#1e293b" horizontal={false} />
                  <XAxis type="number" hide />
                  <YAxis type="category" dataKey="corto" width={142} tickLine={false} axisLine={false}
                         tick={{ fontSize: 10, fill: "#94a3b8" }} />
                  <Tooltip cursor={{ fill: "rgba(56,189,248,.06)" }}
                           content={({ active, payload }) => active && payload?.length ? (
                             <div className="rounded-xl border border-slate-700 bg-slate-950 px-3 py-2 text-xs shadow-2xl">
                               <div className="max-w-[240px] font-medium text-white">{payload[0].payload.n}</div>
                               <div className="mt-1 text-slate-400">
                                 {fFull(payload[0].value)} · {fNum(payload[0].payload.q)} unidades
                                 {payload[0].payload.mg != null && " · margen " + fPct(payload[0].payload.mg)}
                               </div>
                             </div>
                           ) : null} />
                  <Bar dataKey="u" radius={[0, 6, 6, 0]} barSize={18}>
                    {E.art.slice(0, 8).map((a, i) => (
                      <Cell key={a.c} fill={"hsl(" + (198 + i * 13) + " 88% " + (66 - i * 4) + "%)"} />
                    ))}
                  </Bar>
                </BarChart>
              </ResponsiveContainer>
              <div className="mt-3 flex items-center justify-between rounded-xl border border-slate-800 px-3.5 py-2.5 text-xs"
                   style={{ background: "rgba(15,23,42,.6)" }}>
                <span className="text-slate-500">Artículo líder</span>
                <span className="font-semibold text-slate-200">{fPct(maxArt / E.tot, 0)} de la marca</span>
              </div>
            </Tarjeta>
          </div>

          {/* Pedidos + clientes */}
          <div className="mt-5 grid grid-cols-1 gap-5 lg:grid-cols-5">
            <Tarjeta className="lg:col-span-3" titulo="Pedido sugerido"
                     sub="Cobertura objetivo de 3 meses · 45 días de tránsito y compra mensual">
              <div className="overflow-x-auto">
                <table className="w-full text-xs">
                  <thead>
                    <tr className="text-slate-500">
                      <th className="pb-2 text-left font-medium">Artículo</th>
                      <th className="pb-2 text-right font-medium">Demanda/mes</th>
                      <th className="pb-2 text-right font-medium">Stock</th>
                      <th className="pb-2 text-right font-medium">Tránsito</th>
                      <th className="pb-2 text-right font-medium">Cobertura</th>
                      <th className="pb-2 text-right font-medium">Sugerido</th>
                    </tr>
                  </thead>
                  <tbody>
                    {D.ped.slice(0, 8).map((p) => {
                      const riesgo = p.cb != null && p.cb < 1.5;
                      const exceso = p.cb != null && p.cb > 6;
                      return (
                        <tr key={p.c} className="border-t border-slate-800">
                          <td className="py-2.5 pr-3">
                            <div className="max-w-[230px] truncate text-slate-200">{p.n}</div>
                            <div className="text-[11px] text-slate-600">{p.c}</div>
                          </td>
                          <td className="py-2.5 text-right text-slate-300">{fNum(p.d)}</td>
                          <td className="py-2.5 text-right text-slate-400">{fNum(p.st)}</td>
                          <td className="py-2.5 text-right text-slate-400">{fNum(p.tr)}</td>
                          <td className={"py-2.5 text-right font-medium " +
                              (riesgo ? "text-rose-400" : exceso ? "text-amber-400" : "text-emerald-400")}>
                            {p.cb != null ? p.cb.toFixed(1) + " m" : "—"}
                          </td>
                          <td className="py-2.5 text-right font-semibold text-white">{fNum(p.sg)}</td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
              <p className="mt-3 text-xs text-slate-600">
                Rojo: llega por debajo del tiempo de tránsito, hay riesgo de quiebre. Ámbar: más de seis
                meses encima, inventario dormido. Calculado sin EPA, que compra a saltos.
              </p>
            </Tarjeta>

            <Tarjeta className="lg:col-span-2" titulo="Clientes"
                     sub={"Top del período" + (conEpa ? " · EPA incluido" : " · sin EPA")}>
              <div className="mb-4 grid grid-cols-2 gap-3">
                <div className="rounded-xl border border-slate-800 p-3" style={{ background: "rgba(16,185,129,.06)" }}>
                  <div className="text-xs text-slate-500">Activos</div>
                  <div className="mt-0.5 text-2xl font-semibold text-emerald-300">{fNum(activos)}</div>
                </div>
                <div className="rounded-xl border border-slate-800 p-3" style={{ background: "rgba(244,63,94,.06)" }}>
                  <div className="text-xs text-slate-500">Inactivos</div>
                  <div className="mt-0.5 text-2xl font-semibold text-rose-300">{fNum(inactivos)}</div>
                </div>
              </div>
              <div className="space-y-2.5">
                {cliRank.slice(0, 7).map((c, i) => (
                  <div key={c.n} className="flex items-center gap-3">
                    <div className="grid h-7 w-7 shrink-0 place-items-center rounded-lg text-[10px] font-bold text-white"
                         style={{ backgroundImage: "linear-gradient(135deg," + TONOS[i % TONOS.length] + ",#1e293b)" }}>
                      {i + 1}
                    </div>
                    <div className="min-w-0 flex-1">
                      <div className="truncate text-xs font-medium capitalize text-slate-200">{c.n.toLowerCase()}</div>
                      <div className="mt-1 h-1 overflow-hidden rounded-full bg-slate-800">
                        <div className="h-full rounded-full bg-gradient-to-r from-sky-400 to-indigo-400"
                             style={{ width: (c.v / cliRank[0].v) * 100 + "%" }} />
                      </div>
                    </div>
                    <span className="shrink-0 text-xs font-medium text-slate-300">{fUSD(c.v)}</span>
                  </div>
                ))}
              </div>
              <div className="mt-4 rounded-xl border border-slate-800 p-3 text-xs text-slate-500"
                   style={{ background: "rgba(15,23,42,.6)" }}>
                Los 7 primeros son {fPct(cliRank.slice(0, 7).reduce((a, c) => a + c.v, 0) / totCli, 0)} del top 15.
              </div>
            </Tarjeta>
          </div>

          <p className="mt-8 text-center text-xs text-slate-700">
            Datos reales del SIM · marca PCP · Febeca, C.A.
          </p>
        </main>
      </div>
    </div>
  );
}
